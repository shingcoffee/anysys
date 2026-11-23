# Email-only sign-in (no Customer number)

Date: 2026-08-18

## Problem

Public and Devise sign-in currently require an 8-digit Customer number plus email and password. Product rule: email is unique across all tenants. After a successful password (and MFA when required) check, the session belongs to that user’s `customer_id` with no tenant field on the form and no `customer_id` in Devise auth URLs.

## Decisions

1. **Global uniqueness.** `users.email` is unique case-insensitively across the platform. Unique index + model validation. The `(customer_id, email)` unique index is removed. If duplicate emails exist, the migration fails closed; sign-in never picks a “winner.”
2. **Lookup.** `SignInFlow` and `User.find_for_database_authentication` find an active user by email only. `customer_id` comes from the user row after password success. Leftover `customer_number` params are ignored.
3. **Routes.** Devise sessions, passwords, confirmations, and sign-out live at `/auth/...` (no customer id). `POST /sign_in` and `CustomerResolutionsController` are removed. `/` and `/auth/sign_in` both POST to `sessions#create`.
4. **Sign-up stays tenant-scoped.** `GET/POST /:customer_id/auth/sign_up` and `POST /:customer_id/auth` remain. A new account still joins a specific customer. Create fails if the email already exists on any tenant.
5. **Account edit** is `/auth/edit` (signed-in; tenant known from the session).
6. **MFA** stays at `/:customer_id/mfa*` after password success, using the resolved user’s tenant.
7. **Password reset / confirmation / unlock** look up by email globally. Mailer links point at `/auth/...`.
8. **Unauthenticated redirects** go to `/auth/sign_in` (no cid). After success: member → `/:cid/member`, admin/owner → `/:cid/admin` dashboard. Stored location is honored only under that user’s `customer_id`.
9. **Auth-module / reset-disabled tenants.** GET `/auth/sign_in` and GET `/auth/password/new` always render. After email lookup, if that user’s tenant has authentication (or password reset / confirmation resend) disabled, treat as a generic failure / generic “if that email exists” success — do not leak.
10. **Forgot password** is always shown on `/auth/sign_in`. **Create account** is hidden on global sign-in (no tenant to join); it remains on `/:cid/auth/sign_up`.
11. **Errors.** Unknown email, wrong password, inactive, locked, leftover customer_number, and disabled-auth tenant all yield the same generic invalid-credentials message on sign-in.

## Out of scope

- Removing `customer_id` from post-login admin/member URLs
- MFA / trusted-device redesign
- Signup UX beyond uniqueness
- CAPTCHA / rate-limit redesign
- New roles or URL taxonomy changes

## UI

Drop the Customer number input and hint on `/` and `/auth/sign_in`. Intro copy is email + password only (`en` + `zh-CN`). Autofocus email. Remember-me, unconfirmed banner, and password placeholder stay.

## Testing

- Model: global uniqueness; `find_for_database_authentication` by email; recovery without `customer_id`
- SignInFlow: no `customer_id` argument; no `:missing_customer`
- Request: sign-in without `customer_number`; redirect under the user’s tenant; leftover param ignored
- Routes: `/auth/sign_in`, `/auth/password`, `/auth/sign_out`; sign-up still `/:cid/auth/sign_up`
- Mailer bodies: `/auth/password/edit` and `/auth/confirmation` (no cid)
- Factories already sequence emails; specs that create the same email on two customers must be rewritten
