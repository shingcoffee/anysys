# Public customer sign-up: signed self-expiring token

**Date:** 2026-09-01
**Status:** approved (conversation)
**Surface:** public `/auth/sign_up` only. Member sign-up at `/:cid/auth/sign_up` is unchanged.

## Problem

`POST /auth/sign_up` currently creates a Customer, an unconfirmed admin User, reserved roles, required feature modules, and billing onboarding **before** the inbox is proven. A bot can fill the database with junk tenants. Confirmation only blocks sign-in; it does not stop row creation.

## Decision

Prove the inbox with a **signed, encrypted, self-expiring token**. The email lives in the link, not in a table. After the TTL the link is invalid. There is nothing to sweep. Customer + admin User + provisioning happen **only** when the link is opened.

## Flow

1. Visitor submits email on `GET/POST /auth/sign_up`.
2. Controller: kill switch, email format, captcha (fail-closed when platform captcha is configured), IP+email flood throttle.
3. Always redirect to check-email (enumeration-safe). Store the submitted email in the session **only** for displaying the check-email page. Do **not** insert Customer, User, or a pending-signup row.
4. Enqueue mail (`deliver_later`). The job mints `Authentication::CustomerSignupToken.generate(email)` and sends the link. If the email is already a User, the job is a no-op (same HTTP response either way).
5. `GET /auth/sign_up/confirm?token=` decrypts/verifies. Invalid or expired → expired-link page. Valid + unknown email → `CustomerSignup` creates a **confirmed** admin (email already proven) and signs them in. Valid + existing email → do **not** create a second tenant; confirm if needed and sign that user in.
6. Resend on check-email posts to `POST /auth/sign_up/resend` (session email, throttled, same enqueue path). No captcha on resend (session was established after a captcha-gated create).

## Token

- `ActiveSupport::MessageEncryptor` via `Rails.application.key_generator.generate_key("customer_signup", 32)`.
- `encrypt_and_sign({ "email" => normalized_email }, purpose: "customer_signup", expires_in: 3.days)`.
- Purpose string is distinct from MFA reset, campaign unsubscribe, email tracking, and flowchart cipher.
- Encrypt, do not merely sign, so the email is not readable in logs or Referer headers.
- No `jti` / cache nonce. Replay after success is stopped by email uniqueness (second click signs in the existing user).

## Security controls (practical caveats)

| Control | Where |
|---|---|
| Captcha, fail-closed | `POST /auth/sign_up` when `Captcha::ProviderSettings.active` is present. Public signup has no tenant; do **not** require the per-customer captcha feature module. If captcha is not configured, do not block signup (same as Verify `:disabled`). |
| IP + email flood throttle | `Authentication::EmailFloodThrottled` on create and resend. Flow key `"customer_signup"`. Shared "global" tenant bucket (no `customer_id` on this URL). |
| Enumeration | Taken and unknown emails both redirect to check-email. Mail is enqueued, never inline. Job no-ops when the address already exists. |
| Kill switch | Existing `PlatformSettings.customer_signup_enabled?` on new/create/resend/confirm. |
| Distinct purpose | Token cannot be reused as an MFA-reset or unsubscribe token. |

## Out of scope

- Member registration at `/:cid/auth/sign_up` (still Devise confirmable).
- Pending-signup table, disposable-email blocklist, cache `jti`.
- Card-on-file / invite-only / waitlist.
- Changing Devise `confirm_within` for member signup.

## I18n

All new copy under `auth.customer_registrations.*` and `auth.mailer.customer_signup.*` and `auth.flash.customer_signup.*`, both `en` and `zh-CN`. English values are the strings that would otherwise have been hard-coded.
