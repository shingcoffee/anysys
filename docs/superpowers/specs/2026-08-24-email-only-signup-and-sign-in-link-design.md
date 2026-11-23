# Email-only customer sign-up and sign-in link

Date: 2026-08-24

## Problem

Public customer sign-up at `/auth/sign_up` still asks for a password. Founders should submit only an email. After they confirm that inbox they should be signed in. Later visits keep email+password and add a one-time email sign-in link for any confirmed user.

## Decisions

- Sign-up form: email only. No password field.
- Do not generate a random password. Persist the admin with blank `encrypted_password` (column default `""`).
- Confirmation link signs the user in via `FinishesSignIn` (MFA still applies).
- Public sign-in keeps email + password and adds “Email me a sign-in link” for every confirmed user.
- First password can be set on the profile page without `current_password` while `encrypted_password` is blank. After a password is set (profile or forgot-password), later changes require the current password.
- Token storage: hashed `sign_in_token` + `sign_in_token_sent_at` on `users`, issued with `Devise.token_generator`. One outstanding link at a time. TTL 15 minutes.
- Not in scope: restoring typed email codes, passwordless-only sign-in, changing member self-sign-up at `/:cid/auth/sign_up`.

## Flows

1. **Sign up.** POST email → create Customer + unconfirmed admin (no password) → Devise confirmation email → check-inbox page. Not signed in.
2. **First visit.** Confirmation link confirms, then `SignInFlow.complete` + `FinishesSignIn`. MFA/trusted-device rules match password sign-in.
3. **Later visit (password).** Unchanged, except sign-in fails closed when `encrypted_password` is blank (empty password field never authenticates).
4. **Later visit (link).** POST email from the sign-in form → always show check-email. Confirmed active user: send link. Unconfirmed: resend confirmation. Unknown / inactive / auth-disabled tenant: send nothing. GET token → consume once → `FinishesSignIn`.
5. **Set password.** Profile edit hides `current_password` when `encrypted_password` is blank. Setting a password (or completing reset) fills the hash.

## Data

`users`:

- `sign_in_token` string, unique index (NULLs allowed)
- `sign_in_token_sent_at` datetime

`Authentication::User`:

- `attr_accessor :allow_blank_password` — CustomerSignup sets this so create validation does not require a password. All other creates still require one.
- `password_set?` → `encrypted_password.present?`

No new event types. Successful link/confirm sign-in already records `login_succeeded` via `FinishesSignIn`. Request throttle records `throttled`.

## Components

- `Authentication::CustomerSignup` — `call(email:)` only.
- `Authentication::IssueSignInLink` / `Authentication::ConsumeSignInLink`
- `Authentication::SignInLinkMailer` — HTML+text, same visual language as confirmation.
- `Authentication::SignInLinksController` — public `create`, `check_email`, `show`. Dual-bucket `EmailFloodThrottled` (`flow: "sign_in_link"`).
- `Authentication::SignInFlow.complete` — passwordless first factor; **do not skip MFA** (drop the leftover email-code skip). Honor trusted-device cookie.
- `Authentication::ConfirmationsController#show` — confirm, then `complete` + `FinishesSignIn`.
- `Authentication::RegistrationsController#update_resource` — if `password_set?` use `update_with_password`; else drop `current_password` and `update`.
- `SignInFormComponent` — secondary submit `formaction` POST `/auth/sign_in_link`.
- Routes (public): `POST /auth/sign_in_link`, `GET /auth/sign_in_link?token=`, `GET /auth/sign_in_link/check_email`.

## Error handling

- Sign-up validation: email format / uniqueness; taken email creates no customer.
- Kill switch unchanged.
- Sign-in with blank hash → same generic invalid-credentials response as a wrong password.
- Missing / expired / consumed / locked-user token → redirect to sign-in with generic invalid-link flash.
- Link request always redirects to check-email (enumeration-safe), including throttle (generic throttled flash).
- CSRF on POST; token query param already in `filter_parameters` via `:token`.

## Testing

- CustomerSignup: no password, blank hash, still sends confirmation, still rejects taken email / kill switch.
- Request: sign-up form has no password field; confirm signs in; blank-password user cannot POST `/auth/sign_in`.
- Issue/Consume services: confirmed send, unconfirmed resend, unknown no-op, expiry, one-time consume.
- Sign-in form renders the link submit; request specs cover happy path, MFA pending, throttle, invalid token.
- Profile: blank-hash user can set a password without current_password; password-set user still needs it.
- I18n: `en` and `zh-CN` parity for new keys. English values are the former hard-coded strings.

## Out of scope

- Member tenant sign-up password fields
- Rebuilding `authentication_email_sign_in_challenges`
- New audit event names
- Auto-sign-in remember-me on confirm/link (remember_me stays false)
