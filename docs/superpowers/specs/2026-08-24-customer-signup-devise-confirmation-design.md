# Customer sign-up + Devise confirmation (remove email codes)

## Goal

Public organizations can create a tenant at `/auth/sign_up` with email + password. Devise `:confirmable` sends a confirmation **link**. The customer stays inactive until that link is clicked. Member sign-up at `/:customer_id/auth/sign_up` is unchanged. Passwordless email-code sign-in is removed.

## URLs

| Flow | Path |
|------|------|
| Customer (tenant) sign-up | `GET/POST /auth/sign_up` |
| Member sign-up | `GET /:cid/auth/sign_up`, `POST /:cid/auth` |
| Confirm | `GET /auth/confirmation?confirmation_token=` (existing) |
| Sign-in | `GET/POST /auth/sign_in` (password only) |

## Behavior

- Platform owner kill switch (`Authentication::PlatformSettings#allow_customer_signup`, default on) under Maintenance / Platform / Authentication module settings.
- Form: email + password only. Server defaults org name (email local-part), industry (`technology`), first/last name.
- Transaction: inactive `Customer` + unconfirmed `admin` user. Skip Authentication provisioner dummy admin. Never `owner`. Never customer `81721200`.
- Confirmation link confirms the user and activates the customer. Then `/auth/sign_in`.
- Taken email: no orphan tenant.
- Signed-in visitors are sent to their current tenant.
- Sign-in form: remove “Email me a sign-in code”; show customer sign-up link when the kill switch is on.

## Removed

Email sign-in code routes, controller, views, mailer, services, challenge table, i18n, audit event kinds, and specs.
