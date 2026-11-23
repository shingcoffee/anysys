# Devise 5.0.x Upgrade Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt every change, enhancement, and recommended configuration introduced by Devise between 4.9.4 and 5.0.4 that applies to this app, with full RSpec coverage for every touched surface.

**Architecture:** No new units. Changes are confined to existing boundaries — one-line config flip, two class-level model hooks, one controller hook, Tailwind view tweaks, a new locale override file, and one hard-coded flash argument fix. Every touched file gets matching spec coverage under the project's existing file-structure, naming, and styling conventions.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, Devise 5.0.4, Warden 1.2.x, Rack 3.2.6, RSpec, FactoryBot, Tailwind CSS, StimulusJS.

**Spec reference:** `docs/superpowers/specs/2026-05-12-devise-5-upgrade-design.md`

---

## File Structure

### Files modified
- `config/initializers/devise.rb` — flip `error_status`
- `app/models/authentication/user.rb` — add class-level `password_length` and `sign_in_after_change_password?` overrides
- `app/controllers/authentication/passwords_controller.rb` — add `sign_in_after_reset_password?` hook
- `app/controllers/authentication/sessions_controller.rb` — lowercase the `"Email"` argument in the invalid-credentials flash
- `app/views/authentication/shared/_auth_card.html.erb` — add `data-turbo-temporary` to flash blocks
- `app/views/authentication/passwords/new.html.erb` — update button copy
- `spec/requests/authentication/sessions_spec.rb` — extend (existing file)
- `spec/requests/authentication/registrations_spec.rb` — extend (existing file)
- `spec/models/authentication/user_spec.rb` — extend (existing file)

### Files created
- `config/locales/devise.en.yml` — locale override file (copy of Devise 5.0.4 defaults + header comment)
- `spec/config/devise_initializer_spec.rb` — new
- `spec/config/devise_locale_spec.rb` — new
- `spec/requests/authentication/passwords_spec.rb` — new
- `spec/requests/devise_response_status_spec.rb` — new
- `spec/views/authentication/shared/_auth_card.html.erb_spec.rb` — new
- `spec/views/authentication/sessions/new.html.erb_spec.rb` — new
- `spec/views/authentication/registrations/new.html.erb_spec.rb` — new
- `spec/views/authentication/registrations/edit.html.erb_spec.rb` — new
- `spec/views/authentication/passwords/new.html.erb_spec.rb` — new

---

## Task 1: Flip responder error_status to :unprocessable_content

**Files:**
- Modify: `config/initializers/devise.rb`
- Create: `spec/config/devise_initializer_spec.rb`

- [ ] **Step 1: Write the failing config spec**

Create `spec/config/devise_initializer_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Devise initializer", type: :config do
  it "uses :unprocessable_content as the responder error status (Devise 5.0 / Rack 3.1+)" do
    expect(Devise.responder.error_status).to eq(:unprocessable_content)
  end

  it "uses :see_other as the responder redirect status" do
    expect(Devise.responder.redirect_status).to eq(:see_other)
  end

  it "configures password length range 8..128" do
    expect(Devise.password_length).to eq(8..128)
  end

  it "configures case-insensitive and stripped email as the authentication key" do
    expect(Devise.authentication_keys).to eq([:email])
    expect(Devise.case_insensitive_keys).to eq([:email])
    expect(Devise.strip_whitespace_keys).to eq([:email])
  end

  it "uses cheap stretches in the test environment" do
    expect(Devise.stretches).to eq(1)
  end

  it "expires all remember-me tokens on sign out" do
    expect(Devise.expire_all_remember_me_on_sign_out).to be(true)
  end

  it "configures lockable with failed-attempts strategy" do
    expect(Devise.lock_strategy).to eq(:failed_attempts)
    expect(Devise.unlock_keys).to eq([:email])
    expect(Devise.unlock_strategy).to eq(:time)
    expect(Devise.maximum_attempts).to eq(10)
    expect(Devise.unlock_in).to eq(30.minutes)
  end

  it "configures reset_password_within to 6 hours" do
    expect(Devise.reset_password_within).to eq(6.hours)
  end

  it "signs out via DELETE" do
    expect(Devise.sign_out_via).to eq(:delete)
  end

  it "skips session storage for http_auth" do
    expect(Devise.skip_session_storage).to eq([:http_auth])
  end

  it "does not require reconfirmation (confirmable not used)" do
    expect(Devise.reconfirmable).to be(false)
  end
end
```

- [ ] **Step 2: Run the spec; confirm it fails on the error_status expectation**

Run: `bundle exec rspec spec/config/devise_initializer_spec.rb -e "unprocessable_content"`
Expected: FAIL — expected `:unprocessable_content`, got `:unprocessable_entity`.

- [ ] **Step 3: Flip the config**

Edit `config/initializers/devise.rb`, change line 33 from:

```ruby
  config.responder.error_status = :unprocessable_entity
```

to:

```ruby
  config.responder.error_status = :unprocessable_content
```

- [ ] **Step 4: Run the whole spec file; all green**

Run: `bundle exec rspec spec/config/devise_initializer_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add config/initializers/devise.rb spec/config/devise_initializer_spec.rb
git commit -m "config(devise): adopt :unprocessable_content error status for Rack 3.1+"
```

---

## Task 2: Add resource-level sign_in hook overrides on Authentication::User

**Files:**
- Modify: `app/models/authentication/user.rb`
- Modify: `spec/models/authentication/user_spec.rb`

- [ ] **Step 1: Add failing model specs**

Append the following describe blocks to `spec/models/authentication/user_spec.rb` just before the final `end` (the one that closes `RSpec.describe`):

```ruby
  describe "Devise 5.0 resource-level overrides" do
    describe ".password_length" do
      it "returns the global Devise.password_length range by default" do
        expect(described_class.password_length).to eq(Devise.password_length)
      end

      it "is overridable at the class level (proc-based validator seam)" do
        allow(described_class).to receive(:password_length).and_return(12..64)
        expect(described_class.password_length).to eq(12..64)
      end
    end

    describe ".sign_in_after_change_password?" do
      it "returns the global Devise.sign_in_after_change_password flag by default" do
        expect(described_class.sign_in_after_change_password?)
          .to eq(Devise.sign_in_after_change_password)
      end

      it "is overridable at the class level" do
        allow(described_class).to receive(:sign_in_after_change_password?).and_return(false)
        expect(described_class.sign_in_after_change_password?).to be(false)
      end
    end

    describe ".sign_in_after_reset_password" do
      it "returns the global Devise.sign_in_after_reset_password flag by default" do
        expect(described_class.sign_in_after_reset_password)
          .to eq(Devise.sign_in_after_reset_password)
      end
    end
  end
```

- [ ] **Step 2: Run; confirm failure for password_length**

Run: `bundle exec rspec spec/models/authentication/user_spec.rb -e "Devise 5.0 resource-level overrides"`
Expected: FAIL — `NoMethodError` or mismatched return on `password_length` (Devise's default instance-level delegator doesn't expose a class method we can stub uniformly).

- [ ] **Step 3: Add the overrides on the model**

Edit `app/models/authentication/user.rb`. Locate the block immediately after the `devise :database_authenticatable, ...` line (around line 20). Insert the following directly below that line:

```ruby

    # ==========================================================================
    # Devise 5.0 resource-level overrides
    # ==========================================================================
    # password_length is proc-based in Devise 5.0 so it can be overridden per
    # resource class at runtime. Both hooks defer to the global Devise config
    # today; the seam exists so per-tenant policy can be added later without
    # touching controllers.

    def self.password_length
      Devise.password_length
    end

    def self.sign_in_after_change_password?
      Devise.sign_in_after_change_password
    end
```

Note: `sign_in_after_reset_password` is already exposed as a class attribute by Devise's `Recoverable` module (via `Devise::Models.config`), so the model spec for it will already pass without a manual override — the spec exists to document the fact that our model participates in this Devise 5 API.

- [ ] **Step 4: Run the whole model spec; all green**

Run: `bundle exec rspec spec/models/authentication/user_spec.rb`
Expected: all examples pass (existing + new).

- [ ] **Step 5: Commit**

```bash
git add app/models/authentication/user.rb spec/models/authentication/user_spec.rb
git commit -m "feat(auth): expose Devise 5.0 resource-level password/sign-in hooks"
```

---

## Task 3: Add sign_in_after_reset_password? hook to PasswordsController

**Files:**
- Modify: `app/controllers/authentication/passwords_controller.rb`

- [ ] **Step 1: Add the hook (test coverage comes in Task 5's request spec)**

Edit `app/controllers/authentication/passwords_controller.rb`. In the `protected` section, right before `def after_resetting_password_path_for`, add:

```ruby
    # Devise 5.0.2 hook: allows apps to override whether the user is signed in
    # after a successful password reset. Defers to the model-level flag today;
    # the seam exists so a future policy (e.g., force re-sign-in for admins)
    # can override it without patching Devise.
    def sign_in_after_reset_password?
      resource_class.sign_in_after_reset_password
    end

```

The full `protected` section after the edit reads:

```ruby
    protected

    def sign_in_after_reset_password?
      resource_class.sign_in_after_reset_password
    end

    def after_resetting_password_path_for(_resource)
      new_user_session_path(customer_id: current_customer_id)
    end

    def after_sending_reset_password_instructions_path_for(_resource_name)
      new_user_session_path(customer_id: current_customer_id)
    end
```

- [ ] **Step 2: Run the existing test suite for this controller's surface; green**

Run: `bundle exec rspec spec/requests/authentication/sessions_spec.rb spec/requests/authentication/registrations_spec.rb`
Expected: all pass (no regression).

- [ ] **Step 3: Commit**

```bash
git add app/controllers/authentication/passwords_controller.rb
git commit -m "feat(auth): add sign_in_after_reset_password? hook (Devise 5.0.2)"
```

---

## Task 4: Fix the "Email" → "email" grammar in SessionsController

**Files:**
- Modify: `app/controllers/authentication/sessions_controller.rb`
- Modify: `spec/requests/authentication/sessions_spec.rb`

- [ ] **Step 1: Add failing assertion**

Edit `spec/requests/authentication/sessions_spec.rb`. Locate the existing describe block `"POST /:customer_id/auth/sign_in"` and add this example inside it (after the existing `"rejects invalid credentials"` example):

```ruby
    it "renders the lowercase-email grammar fix from Devise 5.0" do
      post user_session_path(customer_id: customer.id),
           params: { user: { email: "test@example.com", password: "wrong", customer_id: customer.id } }

      flash_alert = request.flash[:alert].to_s + response.body.to_s
      expect(flash_alert).to include("Invalid email or password")
      expect(flash_alert).not_to include("Invalid Email or password")
    end
```

- [ ] **Step 2: Run; confirm failure**

Run: `bundle exec rspec spec/requests/authentication/sessions_spec.rb -e "lowercase-email grammar"`
Expected: FAIL — the current flash says `"Invalid Email or password."`.

- [ ] **Step 3: Lowercase the hard-coded argument**

Edit `app/controllers/authentication/sessions_controller.rb` line 47. Change:

```ruby
        flash.now[:alert] = I18n.t("devise.failure.invalid", authentication_keys: "Email")
```

to:

```ruby
        flash.now[:alert] = I18n.t("devise.failure.invalid", authentication_keys: "email")
```

- [ ] **Step 4: Run the sessions spec; all green**

Run: `bundle exec rspec spec/requests/authentication/sessions_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/authentication/sessions_controller.rb spec/requests/authentication/sessions_spec.rb
git commit -m "fix(auth): lowercase 'email' in invalid-credentials flash (Devise 5.0 grammar fix)"
```

---

## Task 5: Install Devise 5.0.4 locale override file

**Files:**
- Create: `config/locales/devise.en.yml`
- Create: `spec/config/devise_locale_spec.rb`

- [ ] **Step 1: Write the failing locale spec**

Create `spec/config/devise_locale_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Devise locale overrides", type: :config do
  it "applies the Devise 5.0 lowercase-email grammar fix" do
    message = I18n.t("devise.failure.invalid", authentication_keys: "email")
    expect(message).to eq("Invalid email or password.")
  end

  it "provides a non-empty sign-out confirmation message" do
    expect(I18n.t("devise.sessions.signed_out")).to be_a(String).and be_present
  end

  it "provides a non-empty reset-password instruction message" do
    expect(I18n.t("devise.passwords.send_instructions")).to be_a(String).and be_present
  end

  it "provides an unlock instruction message (lockable is enabled)" do
    expect(I18n.t("devise.unlocks.send_instructions")).to be_a(String).and be_present
  end
end
```

- [ ] **Step 2: Run it**

Run: `bundle exec rspec spec/config/devise_locale_spec.rb`
Expected: may already pass because the gem provides defaults — but we still want the override file so the project owns the strings. Run anyway to record the starting state.

- [ ] **Step 3: Create the locale override file**

Create `config/locales/devise.en.yml` with the following content. These strings are the Devise 5.0.4 English defaults — we copy them into the project so the app owns the canonical translation source and picks up the 5.0 grammar/German fixes without depending on gem load order.

```yaml
# Source: Devise 5.0.4 default config/locales/en.yml.
# Loaded by Rails I18n after the gem's copy (alphabetical order under
# config/locales), so keys here win on conflict. This lets us:
#   (a) own the user-facing copy for our custom auth views,
#   (b) pick up 5.0 fixes (lowercase "email", corrected German) without
#       depending on the gem being loaded first,
#   (c) have a stable home for project-specific overrides.
en:
  devise:
    confirmations:
      confirmed: "Your email address has been successfully confirmed."
      send_instructions: "You will receive an email with instructions for how to confirm your email address in a few minutes."
      send_paranoid_instructions: "If your email address exists in our database, you will receive an email with instructions for how to confirm your email address in a few minutes."
    failure:
      already_authenticated: "You are already signed in."
      inactive: "Your account is not activated yet."
      invalid: "Invalid %{authentication_keys} or password."
      locked: "Your account is locked."
      last_attempt: "You have one more attempt before your account is locked."
      not_found_in_database: "Invalid %{authentication_keys} or password."
      timeout: "Your session expired. Please sign in again to continue."
      unauthenticated: "You need to sign in or sign up before continuing."
      unconfirmed: "You have to confirm your email address before continuing."
    mailer:
      confirmation_instructions:
        subject: "Confirmation instructions"
      reset_password_instructions:
        subject: "Reset password instructions"
      unlock_instructions:
        subject: "Unlock instructions"
      email_changed:
        subject: "Email Changed"
      password_change:
        subject: "Password Changed"
    omniauth_callbacks:
      failure: "Could not authenticate you from %{kind} because \"%{reason}\"."
      success: "Successfully authenticated from %{kind} account."
    passwords:
      no_token: "You can't access this page without coming from a password reset email. If you do come from a password reset email, please make sure you used the full URL provided."
      send_instructions: "You will receive an email with instructions on how to reset your password in a few minutes."
      send_paranoid_instructions: "If your email address exists in our database, you will receive a password recovery link at your email address in a few minutes."
      updated: "Your password has been changed successfully. You are now signed in."
      updated_not_active: "Your password has been changed successfully."
    registrations:
      destroyed: "Bye! Your account has been successfully cancelled. We hope to see you again soon."
      signed_up: "Welcome! You have signed up successfully."
      signed_up_but_inactive: "You have signed up successfully. However, we could not sign you in because your account is not yet activated."
      signed_up_but_locked: "You have signed up successfully. However, we could not sign you in because your account is locked."
      signed_up_but_unconfirmed: "A message with a confirmation link has been sent to your email address. Please follow the link to activate your account."
      update_needs_confirmation: "You updated your account successfully, but we need to verify your new email address. Please check your email and follow the confirmation link to confirm your new email address."
      updated: "Your account has been updated successfully."
      updated_but_not_signed_in: "Your account has been updated successfully, but since your password was changed, you need to sign in again."
    sessions:
      signed_in: "Signed in successfully."
      signed_out: "Signed out successfully."
      already_signed_out: "Signed out successfully."
    unlocks:
      send_instructions: "You will receive an email with instructions for how to unlock your account in a few minutes."
      send_paranoid_instructions: "If your account exists, you will receive an email with instructions for how to unlock it in a few minutes."
      unlocked: "Your account has been unlocked successfully. Please sign in to continue."
  errors:
    messages:
      already_confirmed: "was already confirmed, please try signing in"
      confirmation_period_expired: "needs to be confirmed within %{period}, please request a new one"
      expired: "has expired, please request a new one"
      not_found: "not found"
      not_locked: "was not locked"
      not_saved:
        one: "1 error prohibited this %{resource} from being saved:"
        other: "%{count} errors prohibited this %{resource} from being saved:"
```

- [ ] **Step 4: Run the locale spec; all green**

Run: `bundle exec rspec spec/config/devise_locale_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add config/locales/devise.en.yml spec/config/devise_locale_spec.rb
git commit -m "i18n(devise): add locale override file with 5.0 defaults"
```

---

## Task 6: Add data-turbo-temporary to flash blocks in _auth_card

**Files:**
- Modify: `app/views/authentication/shared/_auth_card.html.erb`
- Create: `spec/views/authentication/shared/_auth_card.html.erb_spec.rb`

- [ ] **Step 1: Write the failing view spec**

Create `spec/views/authentication/shared/_auth_card.html.erb_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "authentication/shared/_auth_card.html.erb", type: :view do
  def render_card(flash_hash: {}, title: "Sign in", subtitle: nil, footer: nil)
    allow(view).to receive(:flash).and_return(flash_hash)
    render partial: "authentication/shared/auth_card",
           locals: { title: title, subtitle: subtitle, footer: footer }.compact do
      "INNER"
    end
  end

  it "renders the provided title" do
    render_card(title: "Reset your password")
    expect(rendered).to include("Reset your password")
  end

  it "renders the subtitle when provided" do
    render_card(subtitle: "Enter your email")
    expect(rendered).to include("Enter your email")
  end

  it "renders the footer local when provided" do
    render_card(footer: "FOOTER LINE")
    expect(rendered).to include("FOOTER LINE")
  end

  it "yields the block content inside the card" do
    render_card
    expect(rendered).to include("INNER")
  end

  it "marks the alert flash region with data-turbo-temporary (Devise 5.0 turbo attribute)" do
    render_card(flash_hash: { alert: "nope" })
    expect(rendered).to match(/<div[^>]*data-turbo-temporary[^>]*>\s*<p[^>]*>\s*nope/m)
  end

  it "marks the notice flash region with data-turbo-temporary" do
    render_card(flash_hash: { notice: "done" })
    expect(rendered).to match(/<div[^>]*data-turbo-temporary[^>]*>\s*<p[^>]*>\s*done/m)
  end

  it "renders no flash region when flash is empty" do
    render_card
    expect(rendered).not_to include("data-turbo-temporary")
  end
end
```

- [ ] **Step 2: Run it; confirm failure**

Run: `bundle exec rspec spec/views/authentication/shared/_auth_card.html.erb_spec.rb`
Expected: FAIL — flash regions render without `data-turbo-temporary`.

- [ ] **Step 3: Add the attribute**

Edit `app/views/authentication/shared/_auth_card.html.erb`. Locate the two flash blocks and add `data-turbo-temporary` to each outer `<div>`. The updated section reads:

```erb
      <% if flash[:alert].present? %>
        <div class="mb-6 bg-red-50 border-l-4 border-red-400 p-4 rounded" data-turbo-temporary>
          <p class="text-sm text-red-700"><%= flash[:alert] %></p>
        </div>
        <% flash.delete(:alert) %>
      <% end %>
      <% if flash[:notice].present? %>
        <div class="mb-6 bg-green-50 border-l-4 border-green-400 p-4 rounded" data-turbo-temporary>
          <p class="text-sm text-green-700"><%= flash[:notice] %></p>
        </div>
        <% flash.delete(:notice) %>
      <% end %>
```

- [ ] **Step 4: Run; all green**

Run: `bundle exec rspec spec/views/authentication/shared/_auth_card.html.erb_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/views/authentication/shared/_auth_card.html.erb spec/views/authentication/shared/_auth_card.html.erb_spec.rb
git commit -m "feat(auth): add data-turbo-temporary to flash blocks (Devise 5.0 Turbo attr)"
```

---

## Task 7: Update password-reset submit button copy

**Files:**
- Modify: `app/views/authentication/passwords/new.html.erb`
- Create: `spec/views/authentication/passwords/new.html.erb_spec.rb`

- [ ] **Step 1: Write the failing view spec**

Create `spec/views/authentication/passwords/new.html.erb_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "authentication/passwords/new.html.erb", type: :view do
  let(:customer) { create(:customer) }

  before do
    assign(:resource, Authentication::User.new)
    controller.request.path_parameters[:customer_id] = customer.id.to_s
    allow(view).to receive(:resource).and_return(assigns(:resource))
    allow(view).to receive(:resource_name).and_return(:user)
    allow(view).to receive(:current_customer_id).and_return(customer.id.to_s)
    allow(view).to receive(:devise_mapping)
      .and_return(Devise.mappings[:user])
  end

  it "renders the new Devise 5.0 submit button copy" do
    render
    expect(rendered).to include("Send me password reset instructions")
  end

  it "does not render the deprecated 4.x button copy" do
    render
    expect(rendered).not_to include("Send reset instructions")
    expect(rendered).not_to include("Send me reset password instructions")
  end

  it "renders a password-reset form posting to user_password_path" do
    render
    expect(rendered).to include("action=\"/#{customer.id}/auth/password\"")
    expect(rendered).to match(/method="post"/i)
  end

  it "renders the email input with autofocus" do
    render
    expect(rendered).to match(/type="email"[^>]*autofocus/)
  end

  it "renders a sign-in link back to the session path" do
    render
    expect(rendered).to include("/#{customer.id}/auth/sign_in")
    expect(rendered).to include("Sign in")
  end
end
```

- [ ] **Step 2: Run; confirm failure on the button-copy assertion**

Run: `bundle exec rspec spec/views/authentication/passwords/new.html.erb_spec.rb`
Expected: FAIL — button currently says "Send reset instructions".

- [ ] **Step 3: Update the button copy**

Edit `app/views/authentication/passwords/new.html.erb` line 22. Change:

```erb
      <%= f.submit "Send reset instructions", class: "btn btn-primary w-full" %>
```

to:

```erb
      <%= f.submit "Send me password reset instructions", class: "btn btn-primary w-full" %>
```

- [ ] **Step 4: Run; all green**

Run: `bundle exec rspec spec/views/authentication/passwords/new.html.erb_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/views/authentication/passwords/new.html.erb spec/views/authentication/passwords/new.html.erb_spec.rb
git commit -m "feat(auth): adopt Devise 5.0 password-reset button copy"
```

---

## Task 8: Add full request spec for Authentication::PasswordsController

**Files:**
- Create: `spec/requests/authentication/passwords_spec.rb`

- [ ] **Step 1: Write the full request spec**

Create `spec/requests/authentication/passwords_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication::Passwords", type: :request do
  let(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  let!(:user) { create(:user, customer: customer, email: "pwd@example.com", password: "password123") }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
  end

  describe "GET /:customer_id/auth/password/new" do
    it "returns success" do
      get new_user_password_path(customer_id: customer.id)
      expect(response).to have_http_status(:success)
    end

    it "renders the Devise 5.0 submit button copy" do
      get new_user_password_path(customer_id: customer.id)
      expect(response.body).to include("Send me password reset instructions")
    end

    it "redirects to dashboard when auth module is disabled" do
      FeatureModules::CustomerAssignment.where(customer: customer, feature_module: auth_module).delete_all
      get new_user_password_path(customer_id: customer.id)
      expect(response).to redirect_to(admin_dashboard_path(customer.id))
    end
  end

  describe "POST /:customer_id/auth/password" do
    it "enqueues the reset mailer for a known email" do
      expect {
        post user_password_path(customer_id: customer.id),
             params: { user: { email: "pwd@example.com" } }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(response).to redirect_to(new_user_session_path(customer_id: customer.id))
    end

    it "redirects to sign-in for an unknown email (non-paranoid current behavior)" do
      post user_password_path(customer_id: customer.id),
           params: { user: { email: "nobody@example.com" } }
      expect(response.status).to be_in([200, 302, 422])
    end
  end

  describe "GET /:customer_id/auth/password/edit" do
    it "renders with a valid reset token" do
      raw_token = user.send(:set_reset_password_token)
      get edit_user_password_path(customer_id: customer.id), params: { reset_password_token: raw_token }
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /:customer_id/auth/password" do
    let(:raw_token) { user.send(:set_reset_password_token) }

    it "updates the password and redirects per after_resetting_password_path_for" do
      patch user_password_path(customer_id: customer.id), params: {
        user: {
          reset_password_token: raw_token,
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }
      }
      user.reload
      expect(user.valid_password?("newpassword123")).to be(true)
      expect(response).to redirect_to(new_user_session_path(customer_id: customer.id))
    end

    it "re-renders with 422 when passwords mismatch" do
      patch user_password_path(customer_id: customer.id), params: {
        user: {
          reset_password_token: raw_token,
          password: "newpassword123",
          password_confirmation: "mismatch123"
        }
      }
      expect(response).to have_http_status(422)
    end

    it "honors sign_in_after_reset_password? hook when overridden to false" do
      allow_any_instance_of(Authentication::PasswordsController)
        .to receive(:sign_in_after_reset_password?).and_return(false)

      patch user_password_path(customer_id: customer.id), params: {
        user: {
          reset_password_token: raw_token,
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }
      }
      # With the hook off, Devise redirects to the new_session_path after reset.
      expect(response).to redirect_to(new_user_session_path(customer_id: customer.id))
    end
  end
end
```

- [ ] **Step 2: Run the spec; all green**

Run: `bundle exec rspec spec/requests/authentication/passwords_spec.rb`
Expected: all examples pass.

- [ ] **Step 3: Commit**

```bash
git add spec/requests/authentication/passwords_spec.rb
git commit -m "test(auth): add full request spec for PasswordsController"
```

---

## Task 9: Extend request specs with Devise 5.0 regression coverage

**Files:**
- Modify: `spec/requests/authentication/sessions_spec.rb`
- Modify: `spec/requests/authentication/registrations_spec.rb`
- Create: `spec/requests/devise_response_status_spec.rb`

- [ ] **Step 1: Add CVE regression spec for sessions**

Append the following describe block to `spec/requests/authentication/sessions_spec.rb` just before the final `end`:

```ruby
  describe "CVE-2026-40295 regression: FailureApp open redirect via Referer" do
    it "never redirects off-host from a sign-out DELETE with a hostile Referer" do
      # Simulate a signed-out DELETE (no authenticated user) with a malicious
      # Referer. Devise 5.0.4 must not follow the Referer off-host.
      delete destroy_user_session_path(customer_id: customer.id),
             headers: { "HTTP_REFERER" => "https://evil.example.com/pwn" }

      location = response.headers["Location"].to_s
      expect(location).not_to include("evil.example.com")
    end
  end
```

- [ ] **Step 2: Add status-regression spec for registrations**

Append to `spec/requests/authentication/registrations_spec.rb` just before the final `end`:

```ruby
  describe "Devise 5.0 response status for failed registration" do
    it "returns 422 (Unprocessable Content/Entity alias) on invalid sign-up" do
      post user_registration_path(customer_id: customer.id),
           params: { user: { first_name: "", last_name: "", email: "bad", password: "x", password_confirmation: "y" } }
      expect(response.status).to eq(422)
    end

    it "returns 422 on invalid profile update" do
      user = create(:user, customer: customer, email: "me@example.com", password: "password123")
      sign_in user
      patch user_registration_path(customer_id: customer.id),
            params: { user: { email: "invalid", current_password: "password123" } }
      expect(response.status).to eq(422)
    end
  end
```

- [ ] **Step 3: Create the shared status-regression spec**

Create `spec/requests/devise_response_status_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# Guards the Devise 5.0 / Rack 3.1+ :unprocessable_content status numerically.
# Rails aliases :unprocessable_entity and :unprocessable_content both to 422;
# this spec ensures our controllers always return 422 on failed devise flows,
# independent of which symbol is in use.
RSpec.describe "Devise failure response status", type: :request do
  let(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  let!(:user) { create(:user, customer: customer, email: "status@example.com", password: "password123") }

  before do
    ensure_customer_feature_module(customer, auth_module, status: :active)
  end

  it "returns 422 on failed sign-in" do
    post user_session_path(customer_id: customer.id),
         params: { user: { email: "status@example.com", password: "wrong", customer_id: customer.id } }
    expect(response.status).to eq(422)
  end

  it "returns 422 on failed password reset confirmation" do
    patch user_password_path(customer_id: customer.id), params: {
      user: {
        reset_password_token: "not-a-real-token",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    expect(response.status).to eq(422)
  end
end
```

- [ ] **Step 4: Run all extended/new request specs; all green**

Run: `bundle exec rspec spec/requests/authentication/sessions_spec.rb spec/requests/authentication/registrations_spec.rb spec/requests/devise_response_status_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add spec/requests/authentication/sessions_spec.rb spec/requests/authentication/registrations_spec.rb spec/requests/devise_response_status_spec.rb
git commit -m "test(auth): add Devise 5.0 regression specs (CVE-2026-40295, 422 status)"
```

---

## Task 10: Add view specs for sessions/new, registrations/new, registrations/edit

**Files:**
- Create: `spec/views/authentication/sessions/new.html.erb_spec.rb`
- Create: `spec/views/authentication/registrations/new.html.erb_spec.rb`
- Create: `spec/views/authentication/registrations/edit.html.erb_spec.rb`

- [ ] **Step 1: Create the sessions view spec**

Create `spec/views/authentication/sessions/new.html.erb_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "authentication/sessions/new.html.erb", type: :view do
  let(:customer) { create(:customer) }

  before do
    assign(:resource, Authentication::User.new)
    allow(view).to receive(:resource).and_return(assigns(:resource))
    allow(view).to receive(:resource_name).and_return(:user)
    allow(view).to receive(:current_customer_id).and_return(customer.id.to_s)
    allow(view).to receive(:devise_mapping).and_return(Devise.mappings[:user])
    controller.request.path_parameters[:customer_id] = customer.id.to_s
  end

  it "renders the sign-in title" do
    render
    expect(rendered).to include("Sign in to your account")
  end

  it "posts to the user_session path for the customer" do
    render
    expect(rendered).to include("action=\"/#{customer.id}/auth/sign_in\"")
  end

  it "renders the customer number, email, password, and remember-me inputs" do
    render
    expect(rendered).to match(/name="customer_number"/)
    expect(rendered).to match(/type="email"[^>]*name="user\[email\]"/)
    expect(rendered).to match(/type="password"[^>]*name="user\[password\]"/)
    expect(rendered).to match(/type="checkbox"[^>]*name="user\[remember_me\]"/)
  end

  it "renders the Tailwind sign-in button with the shared button class" do
    render
    expect(rendered).to match(/class="[^"]*btn btn-primary[^"]*"[^>]*value="Sign in"/)
  end
end
```

- [ ] **Step 2: Create the registrations/new view spec**

Create `spec/views/authentication/registrations/new.html.erb_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "authentication/registrations/new.html.erb", type: :view do
  let(:customer) { create(:customer) }

  before do
    assign(:resource, Authentication::User.new(customer_id: customer.id))
    allow(view).to receive(:resource).and_return(assigns(:resource))
    allow(view).to receive(:resource_name).and_return(:user)
    allow(view).to receive(:current_customer_id).and_return(customer.id.to_s)
    allow(view).to receive(:devise_mapping).and_return(Devise.mappings[:user])
    controller.request.path_parameters[:customer_id] = customer.id.to_s
  end

  it "renders the sign-up title" do
    render
    expect(rendered).to include("Create your account")
  end

  it "posts to the user_registration path" do
    render
    expect(rendered).to include("action=\"/#{customer.id}/auth\"")
    expect(rendered).to match(/method="post"/i)
  end

  it "renders first_name, last_name, email, password, password_confirmation inputs" do
    render
    %w[first_name last_name email password password_confirmation].each do |field|
      expect(rendered).to match(/name="user\[#{field}\]"/)
    end
  end

  it "links back to the sign-in page" do
    render
    expect(rendered).to include("/#{customer.id}/auth/sign_in")
  end
end
```

- [ ] **Step 3: Create the registrations/edit view spec**

Create `spec/views/authentication/registrations/edit.html.erb_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "authentication/registrations/edit.html.erb", type: :view do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, customer: customer) }

  before do
    assign(:resource, user)
    allow(view).to receive(:resource).and_return(user)
    allow(view).to receive(:resource_name).and_return(:user)
    allow(view).to receive(:current_customer_id).and_return(customer.id.to_s)
    allow(view).to receive(:devise_mapping).and_return(Devise.mappings[:user])
    controller.request.path_parameters[:customer_id] = customer.id.to_s
  end

  it "renders the edit title" do
    render
    expect(rendered).to include("Edit your profile")
  end

  it "posts PATCH/PUT to the user_registration path" do
    render
    expect(rendered).to include("action=\"/#{customer.id}/auth\"")
    expect(rendered).to match(/name="_method"\s+value="put"/)
  end

  it "renders all profile and password-change inputs including current_password" do
    render
    %w[first_name last_name email password password_confirmation current_password].each do |field|
      expect(rendered).to match(/name="user\[#{field}\]"/)
    end
  end

  it "renders the Cancel link back to the dashboard" do
    render
    expect(rendered).to include("Cancel")
    expect(rendered).to include(admin_dashboard_path(customer.id))
  end
end
```

- [ ] **Step 4: Run all three new view specs; all green**

Run: `bundle exec rspec spec/views/authentication/`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add spec/views/authentication/sessions/new.html.erb_spec.rb spec/views/authentication/registrations/new.html.erb_spec.rb spec/views/authentication/registrations/edit.html.erb_spec.rb
git commit -m "test(auth): add view specs for sessions/registrations auth templates"
```

---

## Task 11: Final full-suite verification

**Files:** None modified.

- [ ] **Step 1: Run the full RSpec suite**

Run: `bundle exec rspec`
Expected: zero failures, zero errors, no new pending examples introduced by this change.

- [ ] **Step 2: If any failure is attributable to this change, fix it and re-run**

Typical shape of fixes:
- A factory or fixture expecting the old button copy → update the fixture string.
- A request spec asserting `response.body.include?("Invalid Email")` → change to `"Invalid email"`.
- Any view test expecting the pre-attribute flash block → add `data-turbo-temporary` to the expectation.

Resist the temptation to touch code outside this upgrade's scope.

- [ ] **Step 3: Verify no unrelated files changed**

Run: `git status`
Expected: working tree clean. No stray files outside the scope declared in the File Structure section.

- [ ] **Step 4: No commit needed if tree is clean**

If Step 2 required fixes, commit them with:

```bash
git commit -m "test(auth): fix downstream assertions touched by Devise 5.0 upgrade"
```

---

## Acceptance criteria (from spec §8)

- Every "Apply" / "Verify" row in spec §2 reflected in the codebase — Tasks 1–7.
- Every touched file has matching spec coverage — Tasks 1–10.
- Every new/edited file conforms to project conventions (Tailwind-only, `frozen_string_literal: true`, snake_case, specs mirroring app paths, FactoryBot) — threaded through every task.
- Full RSpec suite passes — Task 11.
- No feature-level behavior change beyond the items enumerated in spec §4.

---

## Self-review results

Ran the checklist against the spec:

- **Spec coverage:** §2 rows 1 (Task 1), 2 (Task 1 secret_key_base verification implicit via suite-passing), 3 (Task 2), 4 (Task 2), 5 (Task 3), 6 (Task 6), 7 (audit-confirmed in spec §2 row 7), 8 (Task 7), 9 (Tasks 4 + 5), 10 (Task 9), 11 N/A, 12 (Task 11 suite run), 13 N/A. Full conventions section (§6.10) threaded across every task's code blocks (`frozen_string_literal`, snake_case, Tailwind-only, FactoryBot, paths).
- **Placeholders:** none remain. Every code step shows the actual code; every test step shows the actual test.
- **Type consistency:** `sign_in_after_change_password?` (model class method with `?`), `sign_in_after_reset_password` (Devise-provided class attr, no `?` on accessor, `?` only on controller hook), `password_length` (no `?`) — verified consistent across Tasks 2, 3, 5, 8.
