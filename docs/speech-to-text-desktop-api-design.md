# Desktop AI Assistant (OAuth PKCE) — Design

Date: 2026-08-26

## Problem

The admin dashboard assistant (typed wording + microphone STT) is cookie-session + Turbo Streams only. The first-party Windows desktop app authenticates with OAuth 2.0 PKCE (`anysys-desktop`) and calls Bearer JSON APIs. It cannot use the assistant today.

This Rails repo exposes JSON APIs and documents them. The Windows GUI is not in this repo.

## Decisions

- Audience: `admin` and `owner` only (web parity). Members stay out.
- Conversation: one thread per `(customer, user)`, shared with the web dashboard.
- Input: typed wording **and** microphone audio (transcribe-then-auto-send, same as web).
- Auth: Bearer-only sibling APIs (cookies rejected), matching `GET /:cid/admin/entity_definitions`.
- Reply delivery: desktop **polls**. No SSE/WebSocket/Turbo for the GUI.

## Architecture

New admin JSON endpoints under `/:customer_id/admin/assistant/`. Controllers include `Oauth::BearerAuthenticatable`. RouteAuthorization still gates `/admin/` as admin-or-owner. Tenant comes from the URL + `TenantContext`. Client-supplied `customer_id` is ignored.

Existing cookie URLs stay unchanged:

- `POST /:cid/admin/modules/speech_to_text/messages`
- `POST /:cid/admin/modules/speech_to_text/transcriptions`

Business logic stays in existing activities (`SendMessage`, `EnqueueTranscription`, `Reply`). New read activities: `ListMessages`, `ShowTranscription`.

Vendor HTTP still never runs on a Puma request thread.

## HTTP contract

All requests: `Authorization: Bearer {access_token}` from the `anysys-desktop` client. Scope remains `profile`.

### `GET /:cid/admin/assistant/messages`

Returns the current user's conversation in that tenant.

```json
{
  "messages": [
    {
      "id": 1,
      "role": "user",
      "body": "How do I create an entity?",
      "status": "complete",
      "created_at": "2026-08-26T12:00:00Z"
    }
  ],
  "pending_reply": true
}
```

- `pending_reply` is true when the last message is `role: "user"` (ReplyJob still running or not yet persisted).
- No conversation yet and the module is available: `200` with `"messages": []`, `"pending_reply": false`.
- Module disabled or no active platform provider: `403` `{ "errors": [...] }` using existing I18n keys (`module_disabled` / `unconfigured`).

### `POST /:cid/admin/assistant/messages`

JSON `{ "body": "..." }`. Calls `SendMessage`. **202** `{ "message_id": 1 }`. Same validation, rate limit (30/hour), and 422/403/429 behavior as the web composer.

### `POST /:cid/admin/assistant/transcriptions`

Multipart: `audio` (required), `duration_seconds` (required, same enqueue rule as web), `language` (optional), `field_dom_id` (optional; default `"desktop"`).

Calls `EnqueueTranscription`. **202** `{ "clip_id": 1 }`. Same 403/422/429 + `error_code` as the web transcribe endpoint.

### `GET /:cid/admin/assistant/transcriptions/:id`

Poll STT job status. Scoped to `customer_id` (URL tenant) **and** `user_id` (token owner).

```json
{ "id": 1, "status": "pending" }
{ "id": 1, "status": "succeeded" }
{ "id": 1, "status": "failed", "error_code": "empty", "errors": ["No speech detected."] }
```

- `404` `{ "error": "not_found" }` if missing or not owned.
- On `succeeded`, the transcript was already handed to `SendMessage`; the client then polls `GET .../messages`.

### Auth matrix

| Caller | Result |
|---|---|
| Valid admin Bearer for that `cid` | allowed |
| Platform owner Bearer for another `cid` | allowed (turns stored for that tenant + owner user) |
| Cookie session, no Bearer | `401` `{ "error": "invalid_token" }` |
| Missing / invalid / wrong-client / inactive user | `401` `{ "error": "invalid_token" }` |
| Member Bearer | `403` `{ "error": "access_denied" }` |
| Admin of another tenant | `403` |

CSRF and MFA-on-request are skipped the same way as entity definitions (MFA already happened at authorize).

## Clip lifecycle

Today `Transcribe` purges audio **and destroys** the clip, so there is nothing to poll.

Change: after the job, **keep the row**, set `status` + `error_code`, purge the audio blob. Still broadcast the Turbo Stream replace so the web widget is unchanged. `SendMessage` still runs on a successful transcript.

`PruneClipsJob` deletes **any** clip older than 15 minutes (pending or finished), not only pending rows.

`error_code` values are existing widget keys: `empty`, `vendor_down`, `disabled`, `generic_error`, `rate_limited`. SendMessage failures after a good transcript map `429 → rate_limited`, `403 → disabled`, else `generic_error`.

## Out of scope

- Windows GUI implementation
- Dual-auth on cookie composer URLs
- SSE / WebSocket
- Member assistant
- Separate desktop-only thread
- New OAuth scopes or clients
- Changing the web dashboard UI
