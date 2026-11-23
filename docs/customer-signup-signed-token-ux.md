# Customer signup signed token — UX spec

**Audience:** public (unauthenticated). Not a module nav surface.
**Visual language:** existing member auth shell. Do **not** introduce shadcn cards, a new color system, or a new page chrome.
**Status:** approved after brainstorming. Frontend implements this spec as-is.

Locked product change: `POST /auth/sign_up` no longer creates a tenant. Submit only emails an encrypted self-expiring link. The tenant is created when the recipient opens `GET /auth/sign_up/confirm?token=…`.

---

## 1. Surface inventory

| Surface | URL | Nav area | Change |
|---|---|---|---|
| Sign-up form | `GET /auth/sign_up` (`new_customer_registration_path`) | public | Keep email-only form. Embed platform captcha inside the form when configured. |
| Check-email | `GET /auth/sign_up/check_email` | public | Same layout. Resend posts to `POST /auth/sign_up/resend` (not Devise confirmation). |
| Expired / invalid link | `GET /auth/sign_up/confirm` failure → `expired.html.erb` (422) | public | **New** page. Same AuthShell. Heading, body, CTA back to create-account. |
| Confirmation email | `Authentication::CustomerSignupMailer#instructions` | public (transactional mail) | Reuse `Authentication::MailerShellComponent` with `scope: :customer_signup`. |
| Kill-switch disabled | `GET /auth/sign_up` when signup is off | public | **No change.** Keep `disabled.html.erb`. |

Out of scope (do not restyle or rewrite):

- Member Devise signup at `/:cid/auth/sign_up`
- Platform sign-in, password reset, MFA, sign-in-link pages
- Admin / member / Settings / Maintenance module areas

---

## 2. Layout spec per surface

All three HTML surfaces wrap content in `Member::AuthShellComponent` with `customer: nil` (brand falls back to `t("member.auth_shell.portal_name")`). Do not fork the shell.

Shared chrome (already implemented — reuse, do not restyle):

```
+------------------------------------------------------------------+
|  [full viewport bg-canvas]                                       |
|                                                                  |
|    +---------------------------+---------------------------+     |
|    | BRAND PANE                | FORM PANE                 |     |
|    | bg-canvas-elevated        | max-w-sm                  |     |
|    |                           |                           |     |
|    | [mark] {brand_name}       | flash alert / notice      |     |
|    |                           | (AuthShell, if present)   |     |
|    | {title}                   |                           |     |
|    | {subtitle}                | {yield: page content}     |     |
|    +---------------------------+---------------------------+     |
+------------------------------------------------------------------+
```

- Mobile / tablet (`< lg`): brand pane stacks **above** the form; `border-b` on the brand pane.
- Desktop (`lg:`): two columns; brand pane left with `border-r`.
- Card: `w-full max-w-4xl rounded-2xl border-border-subtle bg-surface shadow-elevated`.
- Outer padding: `px-4 py-8 sm:px-6 sm:py-12`. Form pane: `px-6 py-8 sm:px-10 sm:py-12`.

Flash (already in the shell — do not duplicate in page ERB):

- `flash[:alert]` → danger-subtle box (`border-danger/20 bg-danger-subtle`, `text-danger`). Used for throttle.
- `flash[:notice]` → member-accent-subtle box. Not required for this flow.

### 2.1 Sign-up form — `new.html.erb`

**Shell copy (existing keys — keep):**

| Slot | Key | English |
|---|---|---|
| title | `auth.customer_registrations.new.shell_title` | Create your account. |
| subtitle | `auth.customer_registrations.new.shell_subtitle` | Enter your email. We'll confirm the inbox, then open your workspace. |

**Form pane:**

```
  Create an account                          text-subtitle
  Already have an account? Sign in.          text-body-sm + accent link

  [ validation errors, if any ]              danger-subtle, first full_messages

  Email *                                    form-label form-label-required
  [ you@example.com                      ]   input-member, autofocus

  [ captcha widget — only if platform        Captcha::WidgetComponent
    captcha is configured ]                  platform: true

  [ Create account                       ]   btn-member w-full justify-center
```

**Data shown**

| Region | Source |
|---|---|
| Email field | `@user.email` (`User` form object; not persisted on submit) |
| Validation banner | `@user.errors.full_messages.first` (invalid email, or confirm-time `CustomerSignup` failure re-rendered here) |
| Captcha | Platform `Captcha::ProviderSettings.active` + provider `widget(...)`. Hidden input `captcha_verify_param`. |

**Field order (locked):** email → captcha widget → submit. Matches `FormFields::FormComponent` (fields, then widget, then submit). Do not put captcha above the email field or below the submit button.

**Actions**

| Kind | Control | Target |
|---|---|---|
| Primary | Submit `Create account` | `POST /auth/sign_up` (`customer_registration_path`) |
| Secondary | `Sign in` text link | `new_user_session_path` |
| Destructive | none | — |

**States**

| State | What the user sees |
|---|---|
| Empty / first visit | Blank email, no error banner, captcha only if platform captcha is configured. |
| Loading (page) | Normal server render. No skeleton. Captcha mount shows `t("captcha.widget.loading")` until the vendor SDK paints. |
| Loading (submit) | Native form post. Do not add a custom spinner. |
| Validation error (422) | Same page; danger banner with the first error; email value preserved. Captcha remounts. |
| Captcha rejected | Controller re-renders `:new` (not `:show`). Same validation banner treatment as today. |
| Captcha not configured | Widget `render?` is false. Form is identical to today's email + submit. |
| Throttled | 302 back to this page; AuthShell alert = `auth.flash.customer_signup.throttled`. |
| Kill switch | This template is **not** used. Existing `disabled.html.erb` stays as-is. |
| Taken email | Same success path as a new email (enumeration-safe): 302 to check-email. No error. |

**Captcha embedding (frontend contract)**

```erb
<%= render Captcha::WidgetComponent.new(platform: true) %>
```

Must sit **inside** the `form_with` so `captcha_verify_param` is submitted. `page:` / `customer_id:` stay unused in platform mode. Do not invent a signup-specific Stimulus controller.

### 2.2 Check-email — `check_email.html.erb`

**Shell copy (existing keys — keep):**

| Slot | Key | English |
|---|---|---|
| title | `auth.customer_registrations.check_email.shell_title` | Please confirm your email. |
| subtitle | `auth.customer_registrations.check_email.shell_subtitle` | Activate your account from the inbox. |

**Form pane:**

```
  Check your inbox                           text-subtitle
  We sent a confirmation link to             text-body-sm
  **{email}**. Click it to activate
  your account.

  [ Resend confirmation                  ]   btn-member w-full justify-center

  Back to sign in                            centered accent text link
```

**Data shown**

| Region | Source |
|---|---|
| Highlighted email | `@email` from `session[:customer_signup_email]` (display only; never a stored pending-signup row) |

`body_html` already wraps `%{email}` in `<strong>`. Keep that interpolation. Do not print the token.

**Actions**

| Kind | Control | Target |
|---|---|---|
| Primary | `Resend confirmation` | `POST /auth/sign_up/resend` (`customer_registration_resend_path`) |
| Secondary | `Back to sign in` | `new_user_session_path` |
| Destructive | none | — |

**Resend form (locked)**

- `form_with url: customer_registration_resend_path, method: :post`.
- Session is the source of truth. Do **not** require `user[email]` in the POST body.
- A hidden `user[email]` is optional as a display fallback only; the controller must still read the session. Prefer omitting it (matches the plan).
- Reuse `t("auth.unconfirmed.resend")` → **Resend confirmation**. Do not add a new resend key.

**States**

| State | What the user sees |
|---|---|
| Happy | Address from session in the body; resend + back-to-sign-in. |
| Empty session on GET | Controller concern (redirect to new). No empty-state illustration. |
| Empty session on resend | Redirect to `new_customer_registration_path`. No extra copy. |
| After resend | Same page again (302). Enumeration-safe: taken and unknown emails look identical. |
| Throttled resend | Redirect to sign-up form with `auth.flash.customer_signup.throttled`. |
| Loading | Native form post. No spinner. |

Layout classes stay as today: heading block `mb-8`, form `flex flex-col gap-3`, footer link `mt-4 text-center text-body-sm`.

### 2.3 Expired / invalid link — **new** `expired.html.erb`

Clone the **disabled** page structure (`disabled.html.erb`), not a form. Same AuthShell, heading + body + one full-width primary control.

**Shell + pane copy (new keys — English locked):**

| Slot | Key | English |
|---|---|---|
| title | `auth.customer_registrations.expired.shell_title` | This link has expired. |
| subtitle | `auth.customer_registrations.expired.shell_subtitle` | Request a new confirmation email to continue. |
| heading | `auth.customer_registrations.expired.heading` | Link expired |
| body | `auth.customer_registrations.expired.body` | That confirmation link is invalid or has expired. Enter your email again to get a new one. |
| CTA | `auth.customer_registrations.expired.cta` | Back to create account |

**Form pane:**

```
  Link expired                               text-subtitle
  That confirmation link is invalid or       text-body-sm
  has expired. Enter your email again
  to get a new one.

  [ Back to create account               ]   btn-member w-full justify-center
                                             → new_customer_registration_path
```

**Data shown**

None from the token. Do not echo the token, the email, or a technical error code. Expired, tampered, blank, and wrong-purpose tokens share this one screen (controller already collapses them to `email.blank?`).

**Actions**

| Kind | Control | Target |
|---|---|---|
| Primary | `Back to create account` | `new_customer_registration_path` (`GET /auth/sign_up`) |
| Secondary | none on this page (disabled sibling also has a single CTA) | — |
| Destructive | none | — |

**States**

| State | What the user sees |
|---|---|
| Invalid / expired / garbage token | This page, HTTP 422. |
| Loading | Instant server render. No spinner. |
| Empty | N/A — always has heading + body + CTA. |
| Kill switch during confirm | Existing disabled page (controller `ensure_customer_signup_enabled`). Not this template. |

Do not add a resend form here. The user must re-enter email on the create-account form so captcha + throttle still apply.

### 2.4 Confirmation email — `customer_signup` mailer

Reuse the existing auth mail card. Do **not** design a new email layout.

**HTML** (`app/views/authentication/customer_signup_mailer/instructions.html.erb`):

```erb
<%= render Authentication::MailerShellComponent.new(
      scope:      :customer_signup,
      email:      @email,
      action_url: customer_registration_confirm_url(token: @token)
    ) %>
```

`MailerShellComponent` already maps scope keys onto `Mailers::ShellComponent` (cream canvas, ivory card, bronze `#92400e` CTA, Georgia title, Anysys monogram). Same card as confirmation / sign-in link / reset password.

**Text** (`instructions.text.erb`) — match `sign_in_link.text.erb`:

```
{greeting}

{instructions}

{absolute confirm URL}

{ignore}

{footer}
```

**Copy (new keys — English locked):**

| Key | English |
|---|---|
| `auth.mailer.customer_signup.subject` | Confirm your Anysys account |
| `auth.mailer.customer_signup.greeting` | Hi %{email}, |
| `auth.mailer.customer_signup.title` | Confirm your email |
| `auth.mailer.customer_signup.instructions` | Confirm this email address to finish creating your organization. This link expires in 3 days. |
| `auth.mailer.customer_signup.action` | Confirm email address |
| `auth.mailer.customer_signup.preheader` | Confirm your email to activate your Anysys account. |
| `auth.mailer.customer_signup.heading` | Account |
| `auth.mailer.customer_signup.fallback` | If the button does not work, copy and paste this link into your browser: |
| `auth.mailer.customer_signup.ignore` | If you did not create this account, you can ignore this email. |
| `auth.mailer.customer_signup.brand` | Anysys |
| `auth.mailer.customer_signup.footer` | Sent by Anysys. This is a transactional message — replies are not monitored. |

Card regions (filled by the shell — frontend does not restyle):

| Region | Key |
|---|---|
| Hidden inbox preview | `preheader` |
| Wordmark | `brand` (monogram = first letter "A") |
| Kicker | `heading` → "Account" |
| Headline | `title` |
| Personalized line | `greeting` with recipient email |
| Body | `instructions` |
| Bronze button | `action` → `customer_registration_confirm_url(token:)` |
| Printed URL | `fallback` + same URL |
| Below-card note | `ignore` |
| Below-card footer | `footer` |

No highlight / facts / `note` block (those are billing / reset-password only).

**States:** mail clients only. If the button is stripped, the fallback URL remains. Do not add a second CTA.

---

## 3. Interaction flow

### 3.1 New email — create account

1. User opens `GET /auth/sign_up`.
2. Types email. Completes captcha if the widget is present.
3. Clicks **Create account**.
4. Server throttles + captcha-gates, enqueues mail, sets `session[:customer_signup_email]`. **No Customer/User row.**
5. 302 → `GET /auth/sign_up/check_email`. Body shows the address.
6. User opens the email, clicks **Confirm email address**.
7. `GET /auth/sign_up/confirm?token=…` verifies the token, creates a confirmed admin + tenant, signs in.
8. Redirect to the post-sign-in destination (`FinishesSignIn` / dashboard). **No interstitial success page.**

### 3.2 Taken email (enumeration-safe)

1. Same as 3.1 steps 1–3.
2. `IssueCustomerSignup` does **not** enqueue mail and does **not** 422.
3. Same 302 + same check-email screen (address still displayed from session).
4. If they later open a leftover valid token for that inbox: confirm signs them in (or confirms if still unconfirmed). No second tenant.

### 3.3 Resend

1. On check-email, click **Resend confirmation**.
2. `POST /auth/sign_up/resend` (session email). Throttle + kill-switch apply.
3. 302 back to check-email. Page looks the same.
4. If session email is blank → 302 to `GET /auth/sign_up`.

### 3.4 Invalid / expired / garbage token

1. User opens `GET /auth/sign_up/confirm?token=…` (missing, expired, tampered, wrong purpose).
2. 422 + `expired.html.erb`.
3. Clicks **Back to create account** → `GET /auth/sign_up`.
4. Re-enters email (captcha/throttle apply again).

### 3.5 Confirm-time provision failure

1. Token is valid but `CustomerSignup.call` fails.
2. Re-render `new.html.erb` at 422 with `@user.errors` in the existing danger banner.
3. User corrects / retries from the form. Do not send them to the expired page.

### 3.6 Sign-in after confirm fails (`SignInFlow` unsuccessful)

1. Tenant/user already created.
2. Redirect to `new_user_session_path`. No extra flash required by this spec (existing sign-in page handles auth).

### 3.7 Validation error on create

1. Email fails `URI::MailTo::EMAIL_REGEXP`.
2. 422 `new.html.erb`; first error in the danger banner; email preserved.
3. No mail, no session write.

### 3.8 Captcha fail-closed

1. Platform captcha configured; token missing/invalid.
2. Re-render `:new` (overridden `handle_captcha_rejection`). Same danger treatment as other create failures.
3. No mail.

### 3.9 Throttle

1. Create or resend exceeds the flood window.
2. 302 to `new_customer_registration_path`.
3. AuthShell alert: **Too many sign-up requests. Please wait a few minutes and try again.**

### 3.10 Kill switch

1. Signup disabled.
2. Existing disabled page (heading + body + **Back to sign in**). No mail, no confirm, no UX change.

### 3.11 Permission / roles

Public URLs. No `owner` / `admin` / `member` gate. Do not add role-specific variants.

---

## 4. Component reuse map

**No new ViewComponents.** Pages stay thin ERB wrappers, same as today's `customer_registrations/*`.

| Piece | Component | Notes |
|---|---|---|
| Split-pane chrome (all 3 HTML pages) | `Member::AuthShellComponent` | `customer: nil`, `title:`, `subtitle:` |
| Email field + submit | Existing helpers in the view | `input-member`, `btn-member`, `form-label form-label-required` |
| Platform captcha | `Captcha::WidgetComponent` | `platform: true` inside the create form only |
| Flash banners | AuthShell built-in + existing `flash` Stimulus | Do not add a second banner system |
| Expired page CTA | `link_to` + `btn-member` | Same pattern as `disabled.html.erb` |
| HTML email card | `Authentication::MailerShellComponent` | `scope: :customer_signup` |
| Email chrome | `Mailers::ShellComponent` | Rendered by the adapter; do not call directly from the mailer view |
| Disabled / kill-switch | existing `disabled.html.erb` | Untouched |

Do **not** reuse `Authentication::SignInFormComponent` (password + remember-me + sign-in-link). Do **not** wrap signup in a shadcn Card.

If `MailerShellComponent` specs enumerate scopes, add `:customer_signup` next to `:confirmation`, `:sign_in_link`, `:reset_password`.

---

## 5. Tailwind & Stimulus notes

### Tailwind (match siblings — no new utilities)

Reuse the classes already on `new.html.erb` / `check_email.html.erb` / `disabled.html.erb` / AuthShell:

| Role | Utilities / tokens |
|---|---|
| Page heading in form pane | `text-subtitle mb-1` |
| Supporting copy | `text-body-sm` |
| Heading block | `mb-8` |
| Form stack | `flex flex-col gap-5` (create) / `gap-3` (resend) |
| Inline validation | `rounded-lg bg-danger-subtle border border-danger/20 p-3` + `text-sm text-danger` |
| Email field | `input-member` (sign-in uses `min-h-11` too; either is fine — prefer current signup `input-member` only) |
| Primary button | `btn-member w-full justify-center` |
| Text links | `font-medium text-member-accent-text hover:underline` |
| Footer link row | `mt-4 text-center text-body-sm` |
| Captcha wrapper | already `my-4` + `min-h-[44px]` on the widget |

Responsive behavior is owned by AuthShell. Page content is a single `max-w-sm` column and stays that way from mobile through desktop. Full-width buttons; no side-by-side button groups.

Do not add custom CSS, `<style>` blocks, or a second CSS framework. Mailer inline styles stay inside `Mailers::ShellComponent` (mail-client exception already documented there).

### Stimulus

| Controller | Where | This flow |
|---|---|---|
| `flash` | AuthShell alert/notice | Already mounted. Used for throttle. |
| Vendor captcha (`captcha_<vendor>_controller`) | `Captcha::WidgetComponent` | Already exists. `platform: true` is the only new hook. |

**Do not add** a `customer-signup` (or similar) Stimulus controller. No client-side token handling, countdown, or resend timer.

I18n in JS is N/A. Captcha loading / hint strings stay on the widget (`captcha.widget.*`).

---

## 6. I18n checklist (Task 3)

Place in `config/locales/auth.en.yml` and matching `auth.zh-CN.yml`. English values must be byte-identical to the plan. zh-CN must be professional (terse, full-width punctuation, canonical terms) — not word-for-word.

### New keys

```yaml
auth.flash.customer_signup.throttled: "Too many sign-up requests. Please wait a few minutes and try again."
auth.customer_registrations.expired.shell_title: "This link has expired."
auth.customer_registrations.expired.shell_subtitle: "Request a new confirmation email to continue."
auth.customer_registrations.expired.heading: "Link expired"
auth.customer_registrations.expired.body: "That confirmation link is invalid or has expired. Enter your email again to get a new one."
auth.customer_registrations.expired.cta: "Back to create account"
auth.mailer.customer_signup.subject: "Confirm your Anysys account"
auth.mailer.customer_signup.greeting: "Hi %{email},"
auth.mailer.customer_signup.title: "Confirm your email"
auth.mailer.customer_signup.instructions: "Confirm this email address to finish creating your organization. This link expires in 3 days."
auth.mailer.customer_signup.action: "Confirm email address"
auth.mailer.customer_signup.preheader: "Confirm your email to activate your Anysys account."
auth.mailer.customer_signup.heading: "Account"
auth.mailer.customer_signup.fallback: "If the button does not work, copy and paste this link into your browser:"
auth.mailer.customer_signup.ignore: "If you did not create this account, you can ignore this email."
auth.mailer.customer_signup.brand: "Anysys"
auth.mailer.customer_signup.footer: "Sent by Anysys. This is a transactional message — replies are not monitored."
```

### Existing keys to reuse (do not rewrite)

| Key | English (already in `auth.en.yml`) |
|---|---|
| `auth.customer_registrations.new.shell_title` | Create your account. |
| `auth.customer_registrations.new.shell_subtitle` | Enter your email. We'll confirm the inbox, then open your workspace. |
| `auth.customer_registrations.new.heading` | Create an account |
| `auth.customer_registrations.new.have_account` | Already have an account? |
| `auth.customer_registrations.new.submit` | Create account |
| `auth.customer_registrations.check_email.shell_title` | Please confirm your email. |
| `auth.customer_registrations.check_email.shell_subtitle` | Activate your account from the inbox. |
| `auth.customer_registrations.check_email.heading` | Check your inbox |
| `auth.customer_registrations.check_email.body_html` | We sent a confirmation link to `<strong>%{email}</strong>`. Click it to activate your account. |
| `auth.sessions.email_placeholder` | you@example.com |
| `auth.common.sign_in` | Sign in |
| `auth.common.back_to_sign_in` | Back to sign in |
| `auth.unconfirmed.resend` | Resend confirmation |
| `auth.customer_registrations.disabled.*` | unchanged kill-switch page |
| `captcha.widget.loading` / `captcha.widget.submit_disabled_hint` | unchanged widget |

---

## 7. Frontend file touch list (for implementers)

- Modify: `app/views/authentication/customer_registrations/new.html.erb` — insert platform captcha inside the form.
- Modify: `app/views/authentication/customer_registrations/check_email.html.erb` — resend URL only.
- Create: `app/views/authentication/customer_registrations/expired.html.erb` — AuthShell + heading/body/CTA.
- Create: `app/views/authentication/customer_signup_mailer/instructions.html.erb` and `.text.erb`.
- Modify: `Captcha::WidgetComponent` platform mode (backend/frontend shared; `render?` skips page toggle + tenant module).
- Modify: `config/locales/auth.en.yml` / `auth.zh-CN.yml`.
- Do **not** edit `disabled.html.erb`.
- Do **not** add Stimulus under `app/javascript/controllers/` for this flow.
