# Customer Signup Signed Token Implementation Plan

> **For agentic workers:** Implement this plan. Do **not** git commit (the human reviewer commits). Do not add a pending-signup table.

**Goal:** Public `/auth/sign_up` proves the inbox with an encrypted self-expiring token and only then creates the tenant.

**Architecture:** `POST /auth/sign_up` throttles + captcha-gates, then enqueues mail containing `Authentication::CustomerSignupToken`. No Customer/User row until `GET /auth/sign_up/confirm`. Existing `CustomerSignup` still provisions the tenant, but creates a **confirmed** admin (email already proven).

**Tech Stack:** Rails 8.1.2, Devise confirmable (member signup unchanged), ActiveSupport::MessageEncryptor, Authentication::Throttle / EmailFloodThrottled, CaptchaProtectable, ViewComponent + Tailwind, I18n en + zh-CN.

## Global Constraints

- Grok 4.6 only; do not switch models.
- No git commit.
- No hard-coded user-facing strings; `en` + `zh-CN` in `config/locales/auth.*.yml`.
- Public URL category: `/auth/sign_up*` stays unauthenticated.
- Do not change `/:cid/auth/sign_up` (member Devise confirmable).
- Do not create a `pending_signups` table or store the email anywhere except the encrypted token and the session display key `session[:customer_signup_email]`.
- Token purpose must be the string `"customer_signup"` (not a Symbol reused from MFA/unsubscribe).
- Captcha on public signup is platform-level (`Captcha::ProviderSettings.active`), not the per-tenant captcha feature module.
- Mail is `deliver_later` only (no inline SMTP on the request).
- Enumeration-safe: taken and unknown emails take the same redirect.
- Surgical: do not refactor unrelated auth code.

## File map

Create:

- `app/services/authentication/customer_signup_token.rb`
- `app/services/authentication/issue_customer_signup.rb`
- `app/mailers/authentication/customer_signup_mailer.rb`
- `app/views/authentication/customer_signup_mailer/instructions.html.erb`
- `app/views/authentication/customer_signup_mailer/instructions.text.erb`
- `app/views/authentication/customer_registrations/expired.html.erb`
- `spec/services/authentication/customer_signup_token_spec.rb`
- `spec/services/authentication/issue_customer_signup_spec.rb`
- `spec/mailers/authentication/customer_signup_mailer_spec.rb`

Modify:

- `app/services/authentication/customer_signup.rb` — skip Devise confirmation; create confirmed admin
- `app/controllers/authentication/customer_registrations_controller.rb`
- `app/controllers/concerns/captcha_protectable.rb` — `:sign_up` with nil customer uses platform settings
- `app/components/captcha/widget_component.rb` — platform embedding (`page:` optional)
- `app/views/authentication/customer_registrations/new.html.erb` — render captcha widget
- `app/views/authentication/customer_registrations/check_email.html.erb` — resend to new path
- `config/routes.rb`
- `config/locales/auth.en.yml` / `auth.zh-CN.yml`
- `spec/services/authentication/customer_signup_spec.rb`
- `spec/requests/authentication/customer_registrations_spec.rb`
- `spec/components/captcha/widget_component_spec.rb`
- `spec/concerns/captcha_protectable_spec.rb`
- `spec/components/authentication/mailer_shell_component_spec.rb` if it enumerates mailer scopes

---

### Task 1: Token + issue mail + confirmed CustomerSignup (backend)

**Files:** create token/issue/mailer (Ruby); modify `CustomerSignup`; specs for those services.

**Interfaces:**

```ruby
# Authentication::CustomerSignupToken
PURPOSE = "customer_signup"
TTL     = 3.days

def self.generate(email)  # -> String (url-safe ciphertext)
def self.verify(token)    # -> String email, or nil if expired/tampered/blank/wrong purpose
def self.normalize(email) # -> stripped downcased string

# Authentication::IssueCustomerSignup
def self.call(email:)     # always returns nil; enqueues mail IFF no User exists for that email

# Authentication::CustomerSignupMailer
def instructions(email, token)  # to: email; uses MailerShellComponent scope: :customer_signup

# Authentication::CustomerSignup
# After successful user.save:
#   user.skip_confirmation! before save (or skip_confirmation_notification! + confirm)
#   do NOT send Devise confirmation_instructions
# User must be confirmed, admin, no password, customer active
```

Token implementation sketch:

```ruby
module Authentication
  class CustomerSignupToken
    PURPOSE = "customer_signup"
    TTL     = 3.days

    def self.generate(email)
      encryptor.encrypt_and_sign(
        { "email" => normalize(email) },
        purpose: PURPOSE,
        expires_in: TTL
      )
    end

    def self.verify(token)
      return nil if token.blank?
      payload = encryptor.decrypt_and_verify(token.to_s, purpose: PURPOSE)
      email = payload.is_a?(Hash) ? payload["email"].to_s : ""
      email.presence
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def self.normalize(email)
      email.to_s.strip.downcase
    end

    def self.encryptor
      secret = Rails.application.key_generator.generate_key(PURPOSE, 32)
      ActiveSupport::MessageEncryptor.new(secret, serializer: JSON)
    end
    private_class_method :encryptor
  end
end
```

Issue service: normalize email; if blank or `User.find_by_normalized_email` present, return; else `token = CustomerSignupToken.generate(email)` and `CustomerSignupMailer.instructions(email, token).deliver_later`.

CustomerSignup `build_user`: call `user.skip_confirmation!` so Devise does not send mail and `confirmed_at` is set. Remove any expectation of a Devise confirmation delivery from `spec/services/authentication/customer_signup_spec.rb`. Spec that says "inactive customer" is stale — keep `be_active`.

Tests (must exist and pass):

- generate/verify round-trip; expired token (travel TTL+1.second) returns nil; tampered ciphertext returns nil; a token generated with a different purpose/key does not verify; email is not plaintext in the token string
- IssueCustomerSignup enqueues mail for a new address; does not enqueue when the address is taken; does not create Customer/User; does not deliver inline
- CustomerSignup creates confirmed admin, no Devise confirmation mail, still one user on the new customer

Do not edit routes, controllers, or views in this task.

---

### Task 2: Routes + controller + captcha/throttle (security)

**Depends on Task 1 interfaces.**

Routes (public, next to existing customer registration routes in `config/routes.rb`):

```ruby
post "/auth/sign_up/resend",
     to: "authentication/customer_registrations#resend",
     as: :customer_registration_resend
get  "/auth/sign_up/confirm",
     to: "authentication/customer_registrations#confirm",
     as: :customer_registration_confirm
```

Controller (`Authentication::CustomerRegistrationsController`):

- `include CaptchaProtectable`
- `include Authentication::EmailFloodThrottled`
- `include Authentication::TrustedDeviceCookieable`
- `include Authentication::FinishesSignIn`
- `protect_with_captcha only: :create, action: :sign_up, fail: :closed`
- `before_action :throttle_customer_signup!, only: %i[create resend]`
- `before_action :ensure_customer_signup_enabled, only: %i[create resend confirm]`
- Override `handle_captcha_rejection` to re-render `:new` with `@user` (not `:show`)

`create`:

```ruby
email = User.normalize-or CustomerSignupToken.normalize(sign_up_params[:email])
unless email.match?(URI::MailTo::EMAIL_REGEXP)
  @user = User.new(email: sign_up_params[:email])
  @user.errors.add(:email, :invalid)
  render :new, status: :unprocessable_entity
  return
end
IssueCustomerSignup.call(email: email)
session[:customer_signup_email] = email
redirect_to customer_registration_check_email_path
```

Taken emails must **not** 422.

`resend`: if session email blank, redirect to new; else `IssueCustomerSignup.call` and redirect to check_email.

`confirm`:

```ruby
email = CustomerSignupToken.verify(params[:token])
return render(:expired, status: :unprocessable_entity) if email.blank?

user = User.find_by_normalized_email(email)
if user.nil?
  result = CustomerSignup.call(email: email)
  unless result.success?
    @user = result.user || User.new(email: email)
    render :new, status: :unprocessable_entity
    return
  end
  user = result.user
elsif !user.confirmed?
  user.confirm
end

result = SignInFlow.complete(user: user, trusted_device_token: trusted_device_token)
if result.success?
  finish_sign_in(result, remember_me: false)
else
  redirect_to new_user_session_path
end
```

`CaptchaProtectable#captcha_required_for_request?`: for `action == :sign_up` when `current_customer_id` is blank, return `Captcha::ProviderSettings.active.present?`. Keep today's tenant-module check for tenant-scoped `:sign_up` / `:page_submit`.

Throttle helper: `throttle_email_flood!(flow: "customer_signup", email: ..., redirect_path: new_customer_registration_path, alert: t("auth.flash.customer_signup.throttled"))`. On create, email comes from params; on resend, from session.

Do not edit ViewComponent templates except if a controller-only stub is required (it is not). Backend services are Task 1's lane — do not rewrite them.

Request specs in this task at least: routing for confirm/resend; POST does not change Customer/User counts; taken email still 302 to check-email; confirm with valid token creates tenant and signs in; expired/garbage token renders expired; kill switch still disables.

---

### Task 3: Check-email, expired page, captcha widget, mailer copy (frontend)

Match existing `Member::AuthShellComponent` + `input-member` / `btn-member` styling. Do **not** introduce a new shadcn page for this surface.

`Captcha::WidgetComponent`: add a platform mode. Suggested:

```ruby
def initialize(page: nil, customer_id: nil, form_action: nil, platform: false)
```

`render?` when `platform:` is true: `settings.present? && widget.present?` (skip page toggle and per-tenant module). `targets_protected_endpoint?` is true when `platform:` is true.

`new.html.erb`: inside the form, `render Captcha::WidgetComponent.new(platform: true)` so the hidden `captcha_verify_param` is submitted.

`check_email.html.erb`: POST to `customer_registration_resend_path` (no `user[email]` needed if session holds it; keep hidden email only if you want a fallback — session is source of truth).

`expired.html.erb`: AuthShell, heading + body + link back to `new_customer_registration_path`.

Mailer views: same as `sign_in_link_mailer`, but `scope: :customer_signup` and `action_url: customer_registration_confirm_url(token: @token)`.

I18n keys (English must be byte-identical to these strings):

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

Matching professional zh-CN in `auth.zh-CN.yml`. Check-email resend button may keep `auth.unconfirmed.resend`.

Update `spec/components/captcha/widget_component_spec.rb` for `platform: true`.
Update mailer_shell scope list if it enumerates scopes.

Do not edit models, CustomerSignup, or routes.

---

### Task 4: QA request/system coverage

Rewrite stale examples in `spec/requests/authentication/customer_registrations_spec.rb` and `spec/services/authentication/customer_signup_spec.rb` if developers missed them.

Must cover:

- POST does not create Customer/User; enqueues mail; check-email shows the address
- Taken email: same 302, no extra Customer, no mail
- Confirm happy path: creates customer+confirmed admin, signed in, dashboard redirect
- Second confirm of same token: no second customer, still signed in
- Garbage/expired token: 422 expired page
- Kill switch: no mail, disabled page
- Throttle: 6th POST in window redirects with throttled flash (use the same cache as Throttle)
- Member `/:cid/auth/sign_up` still creates an unconfirmed user (regression)

---

### Task 5: Release verification

Run targeted RSpec for every file touched, then smoke `GET /auth/sign_up` and `GET /auth/sign_up/confirm` (expect 200 / 422). Restart dev server per AGENTS.md if views changed.
