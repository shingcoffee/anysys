# Email Sign In Code

Public alternative first factor: password **or** a one-time code emailed to the user. TOTP MFA still runs afterward when the account requires it.

## Decisions

- Alternative to password, not a replacement and not a second factor
- Always enabled for every tenant (no Settings toggle)
- Enumeration-safe: any well-formed email reaches the same "enter code" screen; only eligible accounts receive mail
- Eligible = active, confirmed, not locked, Authentication module on for that customer
- Dummy challenge rows for everyone else so send latency matches
- 6-digit numeric code, HMAC-SHA256 at rest, 10-minute TTL, single use, a new send supersedes outstanding codes
- Dual flood throttle on send (5 / 15 min per IP and per email digest) via existing EmailFloodThrottled
- Verify throttle 5 / 15 min per email digest; failed codes do not increment Devise failed_attempts
- Mail via deliver_later; code is not in the subject line
- Session stores only the typed email until verify succeeds; then existing SignInFlow post-auth (trusted device / MFA / dashboard)
- Public URLs under /auth/email_sign_in_code; UI reuses Member::AuthShellComponent and input-otp

## Out of scope

- Magic links
- Per-tenant or per-user opt-in
- Email OTP as an MFA method
- Captcha on this flow
