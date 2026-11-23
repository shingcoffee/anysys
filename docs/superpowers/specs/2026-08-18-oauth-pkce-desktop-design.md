# OAuth 2.0 + PKCE for the Anysys desktop client

**Date:** 2026-08-18
**Status:** Locked for implementation (server-only)

## Goal

This Rails app is the OAuth 2.0 authorization server for a first-party Windows Ruby GUI. The GUI is not in this repo. After a browser login (existing Devise + MFA), the server issues access and refresh tokens so the GUI can keep a persistent session without copying cookies.

Resource APIs for the GUI are out of scope. This slice issues tokens and serves userinfo plus discovery.

GUI protocol: `docs/guides/OAUTH_PKCE_DESKTOP.md`

## Decisions

| Topic | Choice |
|---|---|
| Scope in this repo | Server only + protocol spec for the GUI |
| Grant | Authorization code + PKCE S256. No implicit, password, or client credentials |
| Client | One public client `anysys-desktop`. No secret. No client-management UI |
| Redirect | Loopback `http://127.0.0.1:<port>/callback` and `http://[::1]:<port>/callback` |
| Token product | Access 1 hour (opaque, hashed). Refresh rotating, 90-day idle, 1-year absolute |
| Consent | Skip extra consent after MFA-complete web login (first-party) |
| Who | Any user who can sign in (`owner` / `admin` / `member`) |
| Library | Doorkeeper 5.9 wrapped by thin `Oauth::*` services |

## Architecture

Public URLs (OAuth’s own authentication, not cookie auth on token/userinfo):

- `GET /.well-known/oauth-authorization-server`
- `GET /oauth/authorize` — browser; existing sign-in + MFA
- `POST /oauth/token` — code exchange and refresh
- `POST /oauth/revoke` — RFC 7009
- `GET /oauth/userinfo` — Bearer

HTML admin/member routes stay cookie-only.

Return-to after login/MFA must allow `/oauth/authorize` (today `safe_local_path?` only allows `/:cid/...`, and `reset_session` would drop Devise `user_return_to` unless preserved).

## Security

- PKCE `S256` required; `plain` rejected; `state` required (≥ 16 chars)
- Public client; hashed token secrets; refresh rotated immediately on use
- Reuse of a revoked refresh token revokes the whole token family for that user+client
- Loopback HTTP is allowed (RFC 8252); non-loopback redirects must be HTTPS in production
- Inactive users and tenants with Authentication disabled cannot obtain tokens

## Testing

Request specs cover: discovery, anonymous authorize → sign-in, PKCE happy path, bad verifier, missing PKCE, non-loopback redirect, MFA resume, refresh rotation + reuse, revoke, userinfo, inactive user.
