# Desktop GUI — OAuth 2.0 with PKCE

Protocol for the first-party Windows Ruby GUI. This Rails app is the authorization server. The GUI is a **public** client (no client secret).

## Client

| Field | Value |
|---|---|
| `client_id` | `anysys-desktop` |
| Client type | Public (PKCE is the proof; do not ship a secret) |
| `redirect_uri` | `http://127.0.0.1:<ephemeral-port>/callback` (IPv6 loopback `[::1]` also allowed) |
| Callback path | `/callback` exactly |
| `scope` | `profile` |
| `code_challenge_method` | `S256` only |

Discovery (preferred over hard-coding paths):

```
GET /.well-known/oauth-authorization-server
```

RFC 8414 metadata. Public and static, so it is served `Cache-Control: public, max-age=3600` — cache it for the process lifetime rather than refetching per request.

## Authorization request

1. Generate a `code_verifier` (43–128 chars from `[A-Z] / [a-z] / [0-9] / -._~`).
2. `code_challenge = BASE64URL(SHA256(code_verifier))` with no padding.
3. Generate `state` (≥ 16 cryptographically random characters). Store both `state` and `code_verifier` in memory for this attempt only.
4. Bind an ephemeral loopback HTTP server to `127.0.0.1` with a random free port.
5. Open the system browser to:

```
GET {issuer}/oauth/authorize
  ?response_type=code
  &client_id=anysys-desktop
  &redirect_uri=http://127.0.0.1:{port}/callback
  &scope=profile
  &state={state}
  &code_challenge={challenge}
  &code_challenge_method=S256
```

Omit `response_mode`, or send `response_mode=query`. Nothing else is accepted: a fragment or form_post response cannot deliver the code to a loopback listener. Do not send `family_started_at` — the refresh-family clock is issued by the server and any client value is discarded.

The user signs in with the existing web flow (password or email code, MFA when required). There is no extra consent screen. On success the server renders a short handoff page that navigates the browser to the loopback callback with `code` and `state` (a 302 to `127.0.0.1` is not used — Turbo Drive would swallow that cross-origin redirect). Keep the loopback listener running through MFA; the user may take several minutes.

If the app does not open, the page includes a button that performs the same loopback GET. Reject the callback if `state` does not match.

## Token request

```
POST {issuer}/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code={code}
&redirect_uri={the exact redirect_uri from step 5}
&client_id=anysys-desktop
&code_verifier={verifier}
```

Response:

```json
{
  "access_token": "...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "...",
  "scope": "profile"
}
```

Store tokens in the OS credential store (DPAPI / Windows Credential Manager). Never write them to a plaintext file.

## Calling the server

```
GET {issuer}/oauth/userinfo
Authorization: Bearer {access_token}
```

```json
{
  "sub": "123",
  "email": "user@example.com",
  "email_verified": true,
  "name": "Ada Lovelace",
  "customer_id": "12345678",
  "role": "admin"
}
```

`role` is one of `owner`, `admin`, `member`.

The response is `Cache-Control: no-store` — never persist or proxy-cache it. The token must carry the `profile` scope and must have been issued to `anysys-desktop`; anything else is `401 {"error": "invalid_token"}`, and a valid token missing the scope is `403 {"error": "insufficient_scope"}`.

## Entity definition list (admin / owner)

After sign-in, an `admin` or `owner` token may list the tenant's entity definitions (not entries). Shared definitions are resolved for that tenant (override head if present).

```
GET {issuer}/{customer_id}/admin/entity_definitions
Authorization: Bearer {access_token}
```

```json
{
  "entities": [
    {
      "id": 1,
      "name": "Contact",
      "display_label": "Contact",
      "name_slug": "contact",
      "type": "customer_specific",
      "category": "plain",
      "status": "active",
      "extended_model": null,
      "icon": "custom",
      "color": "#6366f1",
      "description": "...",
      "property_schema": [],
      "attribute_groups": [],
      "associations": [],
      "default_properties": {},
      "referenced_template": null,
      "current_version": { "id": 42, "version_number": 3 }
    }
  ]
}
```

A member token receives `403`. Missing or invalid tokens receive `401` `{ "error": "invalid_token" }`. Cookie sessions are not accepted on this URL.

## AI assistant (admin / owner)

After sign-in, an `admin` or `owner` token may use the same AI assistant as the web dashboard (typed wording and microphone STT). One conversation per `(customer_id, user)` is shared with the browser. Cookie sessions are not accepted. The desktop client **polls** — there is no Turbo Stream or WebSocket.

The speech-to-text module must be enabled for the tenant and a platform STT provider must be active. Otherwise send and history return `403` with `{ "errors": [...] }`.

### History

```
GET {issuer}/{customer_id}/admin/assistant/messages
Authorization: Bearer {access_token}
```

```json
{
  "messages": [
    {
      "id": 1,
      "role": "user",
      "body": "How do I create an entity?",
      "status": "complete",
      "created_at": "2026-08-26T12:00:00Z"
    },
    {
      "id": 2,
      "role": "assistant",
      "body": "Open Maintenance → Entities…",
      "status": "complete",
      "created_at": "2026-08-26T12:00:02Z"
    }
  ],
  "pending_reply": false
}
```

`pending_reply` is `true` when the last turn is the user's and the assistant reply has not been stored yet. An empty conversation is `{ "messages": [], "pending_reply": false }`.

### Send typed wording

```
POST {issuer}/{customer_id}/admin/assistant/messages
Authorization: Bearer {access_token}
Content-Type: application/json

{ "body": "How do I create an entity?" }
```

**202** `{ "message_id": 1 }`. The assistant reply is generated off the request; poll `GET .../messages` until `pending_reply` is false (or a new assistant message appears). Blank body is `422`. Rate limit is 30 user turns per hour (`429`).

### Microphone STT

```
POST {issuer}/{customer_id}/admin/assistant/transcriptions
Authorization: Bearer {access_token}
Content-Type: multipart/form-data

audio: <webm/wav blob>
duration_seconds: <integer>
language: <optional, e.g. en or zh-CN>
```

**202** `{ "clip_id": 1 }`. Then poll:

```
GET {issuer}/{customer_id}/admin/assistant/transcriptions/{clip_id}
Authorization: Bearer {access_token}
```

```json
{ "id": 1, "status": "pending" }
```

```json
{ "id": 1, "status": "succeeded" }
```

```json
{ "id": 1, "status": "failed", "error_code": "empty", "errors": ["No speech detected."] }
```

On `succeeded` the transcript was already posted as a user turn; poll `GET .../messages` for the chat. A missing or other-user clip is `404` `{ "error": "not_found" }`. Clips are deleted about 15 minutes after upload.

A member token receives `403`. Missing or invalid tokens receive `401` `{ "error": "invalid_token" }`.

## Refresh (persistent session)

Access tokens last **1 hour**. Before expiry, or on `401` from `userinfo`:

```
POST {issuer}/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token
&refresh_token={refresh_token}
&client_id=anysys-desktop
```

The response includes a **new** refresh token. Discard the old one immediately.

- Idle lifetime: **90 days** (sliding — each successful refresh resets the idle clock)
- Absolute lifetime: **1 year** from the original authorization (then the user must sign in again)
- If a previously used refresh token is sent again, the server revokes **that refresh chain** — the token you replayed plus everything rotated out of it. Treat it as a forced logout for this installation. The user's other devices and browser sessions are unaffected, so a leaked stale token cannot be used to log them out everywhere.

## Logout

```
POST {issuer}/oauth/revoke
Content-Type: application/x-www-form-urlencoded

token={refresh_or_access_token}
&token_type_hint=refresh_token
&client_id=anysys-desktop
```

Then delete local credentials.

## Errors

Token and authorize errors follow RFC 6749 (`error`, `error_description`). Common cases:

| `error` | Meaning |
|---|---|
| `invalid_client` | Wrong `client_id` |
| `invalid_grant` | Bad/expired code, bad PKCE verifier, expired/reused refresh |
| `invalid_request` | Missing PKCE, missing/short `state`, unsupported `response_mode`, malformed request |
| `invalid_redirect_uri` / `invalid_grant` | Redirect was not loopback `/callback` |
| `unauthorized_client` | Grant type not allowed |

Do not log `code`, `code_verifier`, or tokens.
