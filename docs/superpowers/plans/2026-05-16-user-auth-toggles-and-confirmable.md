# User Auth Toggles + Email Confirmation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add customer-scoped admin toggles for Self sign-up and Forgot password under `/:cid/admin/settings/modules/authentication`; enable Devise `:confirmable` so new sign-ups must click an email link to activate; gate every public surface (form + submission + mailer + post-email endpoint) on the appropriate toggle.

**Architecture:** Two new boolean keys land in the existing `customer_feature_modules.configuration` JSON blob. A small `Authentication::Settings` value object reads them. Devise controllers consult that object via a single `auth_settings` helper. `:confirmable` + `:timeoutable` are added to the User model alongside the existing modules; `:validatable` is intentionally omitted (multi-tenant uniqueness scope already covers it). The existing custom `SessionsController` does not go through Warden's failure flow — it calls `Authentication::SignInFlow` directly — so the unconfirmed-email branch is a simple `confirmed_at?` check after sign-in success, refining the spec's `FailureApp` approach.

**Tech Stack:** Ruby 3.2.8, Rails 8.1.2, Devise 5.0, RSpec, ViewComponent, Tailwind, Trailblazer/Reform (existing), AuthShellComponent (existing).

**Spec:** `docs/superpowers/specs/2026-05-16-user-auth-toggles-and-confirmable-design.md`

---

## File Structure

**Create:**

| Path | Responsibility |
|---|---|
| `app/services/authentication/settings.rb` | Read-only value object exposing `signup_enabled?`, `password_reset_enabled?`, `mfa_enabled?` per customer |
| `app/controllers/authentication/confirmations_controller.rb` | Custom Devise confirmation controller — gates on signup toggle, scopes to tenant |
| `app/views/authentication/registrations/disabled.html.erb` | AuthShell page rendered when sign-up (or confirmation) is disabled |
| `app/views/authentication/passwords/disabled.html.erb` | AuthShell page rendered when password reset is disabled |
| `app/views/authentication/sessions/_unconfirmed.html.erb` | AuthShell partial: "please confirm your email + resend" panel on sign-in |
| `db/migrate/<ts>_add_devise_confirmable_to_users.rb` | Adds confirmation columns + unique index, backfills existing users as confirmed |
| `spec/services/authentication/settings_spec.rb` | Predicate logic for `Authentication::Settings` |
| `spec/requests/authentication/confirmations_spec.rb` | Confirmation flow + toggle gating |
| `spec/system/admin/settings/user_authentication_spec.rb` | End-to-end: admin toggles flags, public surfaces respond accordingly |

**Modify:**

| Path | Change |
|---|---|
| `app/services/feature_modules/authentication/registration.rb` | Add `allow_password_reset` schema key; add `configuration_keys` whitelist |
| `app/models/authentication/user.rb` | Add `:confirmable, :timeoutable` to `devise :...`; add multi-tenant `send_confirmation_instructions`; comment `:validatable` decision |
| `app/controllers/application_controller.rb` | Expose `auth_settings` helper |
| `app/controllers/authentication/registrations_controller.rb` | Use `Authentication::Settings`; render disabled page (200) instead of redirect; flash post sign-up about confirmation |
| `app/controllers/authentication/passwords_controller.rb` | Gate all 4 actions on `password_reset_enabled?`; render disabled page |
| `app/controllers/authentication/sessions_controller.rb` | After `SignInFlow` success, block unconfirmed users; stash email in session; redirect to sign-in for inline panel |
| `app/views/authentication/sessions/new.html.erb` | Hide "Sign up" / "Forgot password?" links per toggles; render `_unconfirmed.html.erb` when session has `:unconfirmed_email` |
| `config/routes.rb` | Add `confirmations: "authentication/confirmations"` to `devise_for :users` |
| `config/initializers/devise.rb` | `confirm_within = 3.days`, `allow_unconfirmed_access_for = 0.days`, `timeout_in = 30.minutes` |
| `app/mailers/application_mailer.rb` | `default from: Devise.mailer_sender` |
| `spec/requests/authentication/registrations_spec.rb` | Update for new confirmation flow (existing users sign-up but cannot sign in until confirmed) |
| `spec/requests/authentication/passwords_spec.rb` | Add toggle-off coverage |
| `spec/requests/authentication/sessions_spec.rb` | Add unconfirmed-user branch coverage |

---

## Task 1: Extend `FeatureModules::Authentication::Registration` schema + whitelist

**Files:**
- Modify: `app/services/feature_modules/authentication/registration.rb`
- Test: `spec/services/feature_modules/authentication/registration_spec.rb` (create or extend if it exists)

- [ ] **Step 1: Check whether a spec exists**

```bash
ls spec/services/feature_modules/authentication/registration_spec.rb 2>/dev/null && echo found || echo missing
```

If `missing`, create the file in step 2. If `found`, append the new tests to it.

- [ ] **Step 2: Write the failing test**

Create or extend `spec/services/feature_modules/authentication/registration_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe FeatureModules::Authentication::Registration do
  describe ".configuration_schema" do
    it "exposes allow_registration with default false" do
      schema = described_class.configuration_schema
      expect(schema["allow_registration"]).to include("type" => "boolean", "default" => false)
    end

    it "exposes allow_password_reset with default true" do
      schema = described_class.configuration_schema
      expect(schema["allow_password_reset"]).to include("type" => "boolean", "default" => true)
    end
  end

  describe ".configuration_keys" do
    it "whitelists every configurable key for ModuleConfigsController" do
      expect(described_class.configuration_keys).to match_array(
        %i[allow_registration allow_password_reset mfa_enabled session_timeout max_login_attempts]
      )
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/services/feature_modules/authentication/registration_spec.rb`

Expected: FAIL — `allow_password_reset` key missing; `configuration_keys` not defined.

- [ ] **Step 4: Implement**

Edit `app/services/feature_modules/authentication/registration.rb`. Replace the `configuration_schema` body and add `configuration_keys`:

```ruby
def self.configuration_schema
  {
    "mfa_enabled"          => { "type" => "boolean", "default" => false,
                                "description" => "Require 2FA/MFA for all users" },
    "session_timeout"      => { "type" => "number",  "default" => 30,
                                "description" => "Session timeout in minutes" },
    "max_login_attempts"   => { "type" => "number",  "default" => 10,
                                "description" => "Max failed login attempts before lockout" },
    "allow_registration"   => { "type" => "boolean", "default" => false,
                                "description" => "Allow visitors to self-register a member account. They must confirm their email by clicking a link before they can sign in." },
    "allow_password_reset" => { "type" => "boolean", "default" => true,
                                "description" => "Allow users to reset their password via an email link." }
  }
end

def self.configuration_keys
  %i[allow_registration allow_password_reset mfa_enabled session_timeout max_login_attempts]
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/feature_modules/authentication/registration_spec.rb`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/feature_modules/authentication/registration.rb \
        spec/services/feature_modules/authentication/registration_spec.rb
git commit -m "feat(auth): add allow_password_reset + configuration_keys whitelist

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: Create `Authentication::Settings` value object

**Files:**
- Create: `app/services/authentication/settings.rb`
- Test: `spec/services/authentication/settings_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/services/authentication/settings_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Authentication::Settings do
  let(:customer) { create(:customer) }

  def assign(config_hash)
    fm = FeatureModules::Module.find_by!(key: "authentication")
    cfm = FeatureModules::CustomerAssignment.find_by!(
      customer_id: customer.id, feature_module_id: fm.id
    )
    cfm.update!(status: :active, configuration: config_hash.to_json)
  end

  describe "#signup_enabled?" do
    it "is false when allow_registration is missing (schema default)" do
      assign({})
      expect(described_class.for(customer.id).signup_enabled?).to eq(false)
    end

    it "is true when allow_registration is true" do
      assign("allow_registration" => true)
      expect(described_class.for(customer.id).signup_enabled?).to eq(true)
    end

    it "is false when the auth module is suspended" do
      fm = FeatureModules::Module.find_by!(key: "authentication")
      cfm = FeatureModules::CustomerAssignment.find_by!(
        customer_id: customer.id, feature_module_id: fm.id
      )
      cfm.update!(status: :suspended, configuration: { "allow_registration" => true }.to_json)
      expect(described_class.for(customer.id).signup_enabled?).to eq(false)
    end

    it "is false when customer_id is blank" do
      expect(described_class.for(nil).signup_enabled?).to eq(false)
    end
  end

  describe "#password_reset_enabled?" do
    it "is true when allow_password_reset is missing (schema default true)" do
      assign({})
      expect(described_class.for(customer.id).password_reset_enabled?).to eq(true)
    end

    it "is false when allow_password_reset is explicitly false" do
      assign("allow_password_reset" => false)
      expect(described_class.for(customer.id).password_reset_enabled?).to eq(false)
    end
  end

  describe "#mfa_enabled?" do
    it "reads mfa_enabled from configuration" do
      assign("mfa_enabled" => true)
      expect(described_class.for(customer.id).mfa_enabled?).to eq(true)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/authentication/settings_spec.rb`

Expected: FAIL — `Authentication::Settings` is not defined.

- [ ] **Step 3: Implement**

Create `app/services/authentication/settings.rb`:

```ruby
# frozen_string_literal: true

# Authentication::Settings
#
# Read-only value object that exposes per-customer authentication toggles
# (sign-up, password reset, MFA) as boolean predicates. Wraps the JSON blob
# in `customer_feature_modules.configuration` so controllers and views never
# reach into the feature-module schema directly.
#
# Usage:
#   auth_settings = Authentication::Settings.for(customer_id)
#   auth_settings.signup_enabled?
#   auth_settings.password_reset_enabled?
#
module Authentication
  class Settings
    MODULE_KEY = "authentication"

    def self.for(customer_id)
      new(customer_id)
    end

    def initialize(customer_id)
      @customer_id = customer_id
    end

    def signup_enabled?
      module_active? && bool(config["allow_registration"], default: false)
    end

    def password_reset_enabled?
      module_active? && bool(config["allow_password_reset"], default: true)
    end

    def mfa_enabled?
      module_active? && bool(config["mfa_enabled"], default: false)
    end

    private

    def module_active?
      assignment&.active?
    end

    def config
      @config ||= assignment&.configuration_json || {}
    end

    def assignment
      return @assignment if defined?(@assignment)
      @assignment = nil and return @assignment if @customer_id.blank?

      fm = FeatureModules::Module.find_by(key: MODULE_KEY)
      return @assignment = nil unless fm

      @assignment = FeatureModules::CustomerAssignment.find_by(
        customer_id: @customer_id, feature_module_id: fm.id
      )
    end

    def bool(value, default:)
      return default if value.nil?
      return value if value == true || value == false

      value.to_s == "true"
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/authentication/settings_spec.rb`

Expected: PASS (4 examples).

- [ ] **Step 5: Commit**

```bash
git add app/services/authentication/settings.rb spec/services/authentication/settings_spec.rb
git commit -m "feat(auth): add Authentication::Settings value object for per-customer toggles

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: Expose `auth_settings` helper on ApplicationController

**Files:**
- Modify: `app/controllers/application_controller.rb`

- [ ] **Step 1: Read the existing controller**

```bash
grep -n "helper_method\|current_customer_id\|class ApplicationController" app/controllers/application_controller.rb | head -20
```

- [ ] **Step 2: Add the helper**

Open `app/controllers/application_controller.rb` and add inside the class body (near other `helper_method` declarations):

```ruby
helper_method :auth_settings

def auth_settings
  @auth_settings ||= Authentication::Settings.for(current_customer_id)
end
```

- [ ] **Step 3: Smoke-check by booting the server**

Run: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails runner 'puts Authentication::Settings.for(81721200).signup_enabled?'`

Expected: prints `false` or `true` with no exception.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/application_controller.rb
git commit -m "feat(auth): expose auth_settings helper on ApplicationController

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: Migration — add Devise confirmable columns + backfill

**Files:**
- Create: `db/migrate/<timestamp>_add_devise_confirmable_to_users.rb`

- [ ] **Step 1: Generate the migration**

Run: `bin/rails generate migration AddDeviseConfirmableToUsers confirmation_token:string confirmed_at:datetime confirmation_sent_at:datetime unconfirmed_email:string`

This creates a file at `db/migrate/<ts>_add_devise_confirmable_to_users.rb`.

- [ ] **Step 2: Replace the migration body**

Edit the generated file. Replace its body entirely with:

```ruby
class AddDeviseConfirmableToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :confirmation_token,   :string
    add_column :users, :confirmed_at,         :datetime
    add_column :users, :confirmation_sent_at, :datetime
    add_column :users, :unconfirmed_email,    :string

    add_index :users, :confirmation_token, unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE users
             SET confirmed_at = CURRENT_TIMESTAMP
           WHERE confirmed_at IS NULL
        SQL
      end
    end
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `bin/rails db:migrate`

Expected output: `== AddDeviseConfirmableToUsers: migrated`

- [ ] **Step 4: Verify the schema**

Run: `bundle exec rails runner 'puts Authentication::User.column_names.grep(/confirm/).sort.inspect'`

Expected: `["confirmation_sent_at", "confirmation_token", "confirmed_at", "unconfirmed_email"]`

Run: `bundle exec rails runner 'puts Authentication::User.where(confirmed_at: nil).count'`

Expected: `0` (every existing user backfilled).

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*_add_devise_confirmable_to_users.rb db/schema.rb
git commit -m "feat(auth): add Devise :confirmable columns + backfill existing users

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: Add `:confirmable` + `:timeoutable` to `Authentication::User` + multi-tenant override

**Files:**
- Modify: `app/models/authentication/user.rb`
- Test: `spec/models/authentication/user_spec.rb` (extend)

- [ ] **Step 1: Find the existing user model spec**

```bash
ls spec/models/authentication/user_spec.rb && grep -n "send_reset_password_instructions" spec/models/authentication/user_spec.rb | head
```

- [ ] **Step 2: Write the failing test**

Append to `spec/models/authentication/user_spec.rb` (at the end of the outermost describe block):

```ruby
  describe ".send_confirmation_instructions" do
    let!(:customer_a) { create(:customer) }
    let!(:customer_b) { create(:customer) }
    let!(:user_a) { create(:authentication_user, customer: customer_a, email: "shared@example.com") }
    let!(:user_b) { create(:authentication_user, customer: customer_b, email: "shared@example.com") }

    it "scopes the lookup to the supplied customer_id and sends the email to the right tenant" do
      expect {
        described_class.send_confirmation_instructions(
          email: "shared@example.com", customer_id: customer_a.id
        )
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      delivery = ActionMailer::Base.deliveries.last
      expect(delivery.to).to eq(["shared@example.com"])

      user_a.reload
      user_b.reload
      expect(user_a.confirmation_token).to be_present
      expect(user_b.confirmation_token).to be_blank
    end

    it "no-ops when customer_id is blank (Current.customer_id unset)" do
      expect {
        described_class.send_confirmation_instructions(email: "shared@example.com")
      }.not_to change { ActionMailer::Base.deliveries.size }
    end
  end
```

(If `factory_bot` factories named `:authentication_user` and `:customer` don't exist, use the existing ones in the project; check `spec/factories/`.)

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/models/authentication/user_spec.rb -e "send_confirmation_instructions"`

Expected: FAIL — `:confirmable` not enabled, no `confirmation_token` is set, mail count is 0.

- [ ] **Step 4: Add `:confirmable` + `:timeoutable` to the devise line**

In `app/models/authentication/user.rb`, replace lines 19–20:

```ruby
    devise :database_authenticatable, :registerable, :recoverable,
           :confirmable, :rememberable, :trackable, :lockable, :timeoutable
```

Add this comment immediately above the `devise :...` line (replacing whatever is there in lines 16–18 if needed):

```ruby
    # ==========================================================================
    # Devise Modules
    # ==========================================================================
    # NOTE: :validatable is intentionally absent. Its uniqueness check on
    # email is global, but this model uses tenant-scoped uniqueness
    # (`uniqueness: { scope: :customer_id }` below). The custom validations
    # in this model cover presence, format, and tenant-scoped uniqueness.
    # Adding :validatable would either duplicate or override that scope and
    # re-introduce cross-tenant collisions.
```

- [ ] **Step 5: Add the multi-tenant `send_confirmation_instructions` override**

In the same file, immediately after the existing `send_unlock_instructions` class method (around lines 142–150), add:

```ruby
    def self.send_confirmation_instructions(attributes = {})
      attrs = normalize_recovery_attributes(attributes)
      customer_id = attrs.delete(:customer_id).presence || Current.customer_id
      return new unless customer_id.present?

      user = scoped_recovery_lookup(customer_id, attrs[:email])
      user&.send_confirmation_instructions
      user || new.tap { |u| u.errors.add(:email, :not_found) }
    end
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bundle exec rspec spec/models/authentication/user_spec.rb -e "send_confirmation_instructions"`

Expected: PASS (2 examples).

- [ ] **Step 7: Commit**

```bash
git add app/models/authentication/user.rb spec/models/authentication/user_spec.rb
git commit -m "feat(auth): add :confirmable + :timeoutable to User; multi-tenant confirm scope

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: Configure Devise initializer

**Files:**
- Modify: `config/initializers/devise.rb`

- [ ] **Step 1: Add the new settings**

Open `config/initializers/devise.rb`. After the existing `config.reset_password_within = 6.hours` line (near line 29), add:

```ruby
  # ==========================================================================
  # :confirmable
  # ==========================================================================
  # Strict policy: confirmation required before any sign-in. The toggle
  # `allow_registration` (per-customer) gates whether the sign-up form +
  # confirmation routes are available; once a user signs up, they cannot
  # sign in until they click the link in the email.
  config.confirm_within = 3.days
  config.allow_unconfirmed_access_for = 0.days

  # ==========================================================================
  # :timeoutable
  # ==========================================================================
  # Idle-session expiry. Per-customer override is a follow-up via the
  # existing `session_timeout` config key; today this is platform-wide.
  config.timeout_in = 30.minutes
```

- [ ] **Step 2: Verify Devise still boots**

Run: `bin/rails runner 'puts Devise.confirm_within.inspect; puts Devise.allow_unconfirmed_access_for.inspect; puts Devise.timeout_in.inspect'`

Expected:

```
3 days
0 days
30 minutes
```

- [ ] **Step 3: Commit**

```bash
git add config/initializers/devise.rb
git commit -m "feat(auth): configure Devise confirm_within, strict allow_unconfirmed=0, timeout_in

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 7: Update `ApplicationMailer.default from:`

**Files:**
- Modify: `app/mailers/application_mailer.rb`

- [ ] **Step 1: Replace the placeholder**

Open `app/mailers/application_mailer.rb`. Replace the file with:

```ruby
class ApplicationMailer < ActionMailer::Base
  default from: -> { Devise.mailer_sender }
  layout "mailer"
end
```

(The lambda defers evaluation until send-time so it works regardless of load order.)

- [ ] **Step 2: Verify**

Run: `bin/rails runner 'puts ApplicationMailer.default[:from].call'`

Expected: `noreply@anysys.com`

- [ ] **Step 3: Commit**

```bash
git add app/mailers/application_mailer.rb
git commit -m "feat(auth): unify mailer From with Devise.mailer_sender

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 8: Add `confirmations` route + custom controller + disabled view

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/authentication/confirmations_controller.rb`
- Create: `app/views/authentication/registrations/disabled.html.erb`
- Test: `spec/requests/authentication/confirmations_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/requests/authentication/confirmations_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Authentication::Confirmations", type: :request do
  let(:customer) { create(:customer) }
  let!(:user) do
    create(:authentication_user, customer: customer, email: "newuser@example.com",
           confirmed_at: nil, confirmation_token: "valid-token-123",
           confirmation_sent_at: 1.minute.ago)
  end

  def set_signup(enabled)
    fm = FeatureModules::Module.find_by!(key: "authentication")
    cfm = FeatureModules::CustomerAssignment.find_by!(
      customer_id: customer.id, feature_module_id: fm.id
    )
    cfm.update!(status: :active,
                configuration: { "allow_registration" => enabled }.to_json)
  end

  describe "GET /:cid/auth/confirmation" do
    context "when sign-up is enabled" do
      before { set_signup(true) }

      it "confirms the user with a valid token" do
        get "/#{customer.id}/auth/confirmation", params: { confirmation_token: "valid-token-123" }
        expect(response).to redirect_to(new_user_session_path(customer_id: customer.id))
        expect(user.reload.confirmed_at).to be_present
      end
    end

    context "when sign-up is disabled" do
      before { set_signup(false) }

      it "renders the disabled page even with a valid token" do
        get "/#{customer.id}/auth/confirmation", params: { confirmation_token: "valid-token-123" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Sign-up is currently disabled")
        expect(user.reload.confirmed_at).to be_nil
      end
    end
  end

  describe "POST /:cid/auth/confirmation" do
    context "when sign-up is enabled" do
      before { set_signup(true) }

      it "resends the confirmation email scoped to the tenant" do
        expect {
          post "/#{customer.id}/auth/confirmation",
               params: { user: { email: "newuser@example.com" } }
        }.to change { ActionMailer::Base.deliveries.size }.by(1)
      end
    end

    context "when sign-up is disabled" do
      before { set_signup(false) }

      it "renders disabled page and sends no email" do
        expect {
          post "/#{customer.id}/auth/confirmation",
               params: { user: { email: "newuser@example.com" } }
        }.not_to change { ActionMailer::Base.deliveries.size }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Sign-up is currently disabled")
      end
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/requests/authentication/confirmations_spec.rb`

Expected: FAIL — route does not exist or controller missing.

- [ ] **Step 3: Add the route**

Edit `config/routes.rb`. Find the `devise_for :users, ...` block (around lines 62–69) and update the `controllers:` hash to include `confirmations`:

```ruby
  devise_for :users, path: ":customer_id/auth",
    class_name: "Authentication::User",
    constraints: { customer_id: /\d{8}/ },
    controllers: {
      sessions:      "authentication/sessions",
      registrations: "authentication/registrations",
      passwords:     "authentication/passwords",
      confirmations: "authentication/confirmations"
    }
```

- [ ] **Step 4: Create the disabled view**

Create `app/views/authentication/registrations/disabled.html.erb`:

```erb
<%= render Member::AuthShellComponent.new(
      customer: current_customer,
      title:    "Sign-up is paused.",
      subtitle: "This organization isn't accepting new accounts right now."
    ) do %>
  <div class="mb-8">
    <h2 class="text-subtitle mb-1">Sign-up is currently disabled</h2>
    <p class="text-body-sm">
      Sign-up is currently disabled for this organization. Please contact your administrator
      if you need an account.
    </p>
  </div>

  <%= link_to "Back to sign in",
        new_user_session_path(customer_id: current_customer_id),
        class: "btn-member w-full justify-center" %>
<% end %>
```

- [ ] **Step 5: Create the controller**

Create `app/controllers/authentication/confirmations_controller.rb`:

```ruby
# frozen_string_literal: true

module Authentication
  class ConfirmationsController < Devise::ConfirmationsController
    include TenantContext

    layout "application"

    before_action :check_auth_enabled
    before_action :check_signup_allowed

    protected

    # Devise defaults to redirecting to root after a successful confirmation.
    # Send users to sign-in instead so they have a clear next step.
    def after_confirmation_path_for(_resource_name, _resource)
      new_user_session_path(customer_id: current_customer_id)
    end

    def after_resending_confirmation_instructions_path_for(_resource_name)
      new_user_session_path(customer_id: current_customer_id)
    end

    # Devise reads :customer_id from this hash before delegating to
    # User.send_confirmation_instructions, where the multi-tenant override
    # uses it to scope the lookup.
    def resource_params
      params.require(:user).permit(:email).merge(customer_id: current_customer_id)
    end

    private

    def check_auth_enabled
      return if FeatureModules::Module.enabled?(key: "authentication", customer_id: current_customer_id)

      redirect_to admin_dashboard_path(current_customer_id),
                  notice: "Authentication is not enabled for this account."
    end

    def check_signup_allowed
      return if Authentication::Settings.for(current_customer_id).signup_enabled?

      render "authentication/registrations/disabled", status: :ok
    end
  end
end
```

- [ ] **Step 6: Run the test**

Run: `bundle exec rspec spec/requests/authentication/confirmations_spec.rb`

Expected: PASS (4 examples).

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb \
        app/controllers/authentication/confirmations_controller.rb \
        app/views/authentication/registrations/disabled.html.erb \
        spec/requests/authentication/confirmations_spec.rb
git commit -m "feat(auth): add ConfirmationsController + disabled page; gate by signup toggle

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 9: Switch RegistrationsController to render disabled page; refresh sign-up flash

**Files:**
- Modify: `app/controllers/authentication/registrations_controller.rb`
- Test: `spec/requests/authentication/registrations_spec.rb` (update)

- [ ] **Step 1: Read existing test to understand current expectations**

```bash
cat spec/requests/authentication/registrations_spec.rb
```

- [ ] **Step 2: Replace `check_registration_allowed` body**

Open `app/controllers/authentication/registrations_controller.rb`. Replace the `check_registration_allowed` private method with:

```ruby
    def check_registration_allowed
      return if Authentication::Settings.for(current_customer_id).signup_enabled?

      render "authentication/registrations/disabled", status: :ok
    end
```

(Remove the old `config = ...` body. The behavior is now: render the disabled page in-place rather than redirect.)

- [ ] **Step 3: Update the post-create flash**

In the same file, replace the `set_flash_message!(:notice, :signed_up)` line in `create` and the redirect target. The new behavior: redirect to sign-in with the "please confirm" flash, instead of signing the user in (Devise's `:confirmable` will refuse anyway). Replace the body of `create` with:

```ruby
    # POST /:customer_id/auth/sign_up
    def create
      build_resource(sign_up_params)
      resource.customer_id = current_customer_id

      resource.save
      if resource.persisted?
        assign_member_role!(resource)
        flash[:notice] = "We sent a confirmation link to #{resource.email}. " \
                         "Please click it to activate your account."
        respond_with resource, location: new_user_session_path(customer_id: current_customer_id)
      else
        clean_up_passwords resource
        set_minimum_password_length
        render :new, status: :unprocessable_entity
      end
    end
```

- [ ] **Step 4: Update the spec**

Replace the toggle-off test in `spec/requests/authentication/registrations_spec.rb` to expect the in-place disabled page (not a redirect). Add coverage that role=admin is rejected. Inside the existing top-level describe block:

```ruby
  describe "GET /:cid/auth/sign_up" do
    let(:customer) { create(:customer) }

    def set_signup(enabled)
      fm = FeatureModules::Module.find_by!(key: "authentication")
      cfm = FeatureModules::CustomerAssignment.find_by!(
        customer_id: customer.id, feature_module_id: fm.id
      )
      cfm.update!(status: :active,
                  configuration: { "allow_registration" => enabled }.to_json)
    end

    it "renders the disabled page when allow_registration is false" do
      set_signup(false)
      get "/#{customer.id}/auth/sign_up"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign-up is currently disabled")
    end

    it "renders the form when allow_registration is true" do
      set_signup(true)
      get "/#{customer.id}/auth/sign_up"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create your account")
    end
  end

  describe "POST /:cid/auth/sign_up" do
    let(:customer) { create(:customer) }

    before do
      fm = FeatureModules::Module.find_by!(key: "authentication")
      cfm = FeatureModules::CustomerAssignment.find_by!(
        customer_id: customer.id, feature_module_id: fm.id
      )
      cfm.update!(status: :active,
                  configuration: { "allow_registration" => true }.to_json)
    end

    let(:valid_params) do
      { user: { first_name: "Pat", last_name: "Lee", email: "pat@example.com",
                password: "Password123!", password_confirmation: "Password123!" } }
    end

    it "creates an unconfirmed user and sends one confirmation email" do
      expect {
        post "/#{customer.id}/auth/sign_up", params: valid_params
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      user = Authentication::User.find_by(email: "pat@example.com")
      expect(user).to be_present
      expect(user.confirmed_at).to be_nil
      expect(user.confirmation_token).to be_present
      expect(user.member?).to eq(true)
    end

    it "redirects to sign-in with a 'please confirm' flash" do
      post "/#{customer.id}/auth/sign_up", params: valid_params
      expect(response).to redirect_to(new_user_session_path(customer_id: customer.id))
      follow_redirect!
      expect(flash[:notice]).to include("confirmation link")
    end

    it "does NOT sign the new user in until confirmed" do
      post "/#{customer.id}/auth/sign_up", params: valid_params
      get "/#{customer.id}/member"
      expect(response).not_to have_http_status(:ok)
    end

    it "ignores any role parameter and only assigns :member" do
      malicious = valid_params.deep_dup
      malicious[:user][:role] = "admin"
      malicious[:role] = "admin"
      post "/#{customer.id}/auth/sign_up", params: malicious
      user = Authentication::User.find_by(email: "pat@example.com")
      expect(user.member?).to eq(true)
      expect(user.admin?).to eq(false)
      expect(user.owner?).to eq(false)
    end
  end
```

(Delete or rewrite any pre-existing assertions in this file that conflict. Per the user's stale-test policy: rewrite, don't revert.)

- [ ] **Step 5: Run the spec**

Run: `bundle exec rspec spec/requests/authentication/registrations_spec.rb`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/authentication/registrations_controller.rb \
        spec/requests/authentication/registrations_spec.rb
git commit -m "feat(auth): render disabled page in place; require email confirmation post sign-up

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 10: Gate PasswordsController on `password_reset_enabled?`

**Files:**
- Modify: `app/controllers/authentication/passwords_controller.rb`
- Create: `app/views/authentication/passwords/disabled.html.erb`
- Test: `spec/requests/authentication/passwords_spec.rb` (extend)

- [ ] **Step 1: Write the failing test**

Append to `spec/requests/authentication/passwords_spec.rb`:

```ruby
  describe "toggle gating" do
    let(:customer) { create(:customer) }
    let!(:user) { create(:authentication_user, customer: customer, email: "user@example.com") }

    def set_reset(enabled)
      fm = FeatureModules::Module.find_by!(key: "authentication")
      cfm = FeatureModules::CustomerAssignment.find_by!(
        customer_id: customer.id, feature_module_id: fm.id
      )
      cfm.update!(status: :active,
                  configuration: { "allow_password_reset" => enabled }.to_json)
    end

    context "when allow_password_reset is false" do
      before { set_reset(false) }

      it "GET /password/new renders disabled page" do
        get "/#{customer.id}/auth/password/new"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Password reset is currently disabled")
      end

      it "POST /password renders disabled page and sends no email" do
        expect {
          post "/#{customer.id}/auth/password", params: { user: { email: user.email } }
        }.not_to change { ActionMailer::Base.deliveries.size }
        expect(response.body).to include("Password reset is currently disabled")
      end

      it "GET /password/edit?token=… renders disabled page even with a valid token" do
        token = user.send(:set_reset_password_token)
        get "/#{customer.id}/auth/password/edit", params: { reset_password_token: token }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Password reset is currently disabled")
      end

      it "PATCH /password renders disabled page and does not change the password" do
        token = user.send(:set_reset_password_token)
        old_encrypted = user.encrypted_password
        patch "/#{customer.id}/auth/password",
              params: { user: { reset_password_token: token,
                                password: "NewPassword123!",
                                password_confirmation: "NewPassword123!" } }
        expect(response.body).to include("Password reset is currently disabled")
        expect(user.reload.encrypted_password).to eq(old_encrypted)
      end
    end

    context "when allow_password_reset is true" do
      before { set_reset(true) }

      it "POST /password sends a reset email" do
        expect {
          post "/#{customer.id}/auth/password", params: { user: { email: user.email } }
        }.to change { ActionMailer::Base.deliveries.size }.by(1)
      end
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/requests/authentication/passwords_spec.rb -e "toggle gating"`

Expected: FAIL — gating not yet present, disabled view missing.

- [ ] **Step 3: Create the disabled view**

Create `app/views/authentication/passwords/disabled.html.erb`:

```erb
<%= render Member::AuthShellComponent.new(
      customer: current_customer,
      title:    "Password reset is paused.",
      subtitle: "This organization has password reset turned off."
    ) do %>
  <div class="mb-8">
    <h2 class="text-subtitle mb-1">Password reset is currently disabled</h2>
    <p class="text-body-sm">
      Password reset is currently disabled for this organization. Please contact your
      administrator for help recovering your account.
    </p>
  </div>

  <%= link_to "Back to sign in",
        new_user_session_path(customer_id: current_customer_id),
        class: "btn-member w-full justify-center" %>
<% end %>
```

- [ ] **Step 4: Add the gate**

Edit `app/controllers/authentication/passwords_controller.rb`. Add a second `before_action`:

```ruby
    before_action :check_auth_enabled
    before_action :check_password_reset_allowed
```

Add the private method at the bottom of the class:

```ruby
    private

    def check_password_reset_allowed
      return if Authentication::Settings.for(current_customer_id).password_reset_enabled?

      render "authentication/passwords/disabled", status: :ok
    end
```

- [ ] **Step 5: Run the spec**

Run: `bundle exec rspec spec/requests/authentication/passwords_spec.rb`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/authentication/passwords_controller.rb \
        app/views/authentication/passwords/disabled.html.erb \
        spec/requests/authentication/passwords_spec.rb
git commit -m "feat(auth): gate password reset surface on per-customer toggle

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 11: SessionsController — block unconfirmed users + render inline panel

**Files:**
- Modify: `app/controllers/authentication/sessions_controller.rb`
- Create: `app/views/authentication/sessions/_unconfirmed.html.erb`
- Modify: `app/views/authentication/sessions/new.html.erb`
- Test: `spec/requests/authentication/sessions_spec.rb` (extend)

- [ ] **Step 1: Write the failing test**

Append to `spec/requests/authentication/sessions_spec.rb`:

```ruby
  describe "unconfirmed user flow" do
    let(:customer) { create(:customer) }
    let!(:user) do
      create(:authentication_user, customer: customer,
             email: "pending@example.com",
             password: "Password123!",
             confirmed_at: nil,
             confirmation_token: "valid-token", confirmation_sent_at: 1.minute.ago)
    end

    before do
      fm = FeatureModules::Module.find_by!(key: "authentication")
      cfm = FeatureModules::CustomerAssignment.find_by!(
        customer_id: customer.id, feature_module_id: fm.id
      )
      cfm.update!(status: :active,
                  configuration: { "allow_registration" => true }.to_json)
    end

    it "blocks sign-in for an unconfirmed user and stashes email in session" do
      post "/#{customer.id}/auth/sign_in",
           params: { user: { email: "pending@example.com", password: "Password123!" } }
      expect(response).to redirect_to(new_user_session_path(customer_id: customer.id))

      follow_redirect!
      expect(response.body).to include("Please confirm your email")
      expect(response.body).to include("Resend confirmation")
    end

    it "after confirmation, sign-in succeeds" do
      user.update!(confirmed_at: Time.current)
      post "/#{customer.id}/auth/sign_in",
           params: { user: { email: "pending@example.com", password: "Password123!" } }
      # Existing controller redirects to /:cid/member for member role
      expect(response.status).to be_in([302, 303])
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/requests/authentication/sessions_spec.rb -e "unconfirmed user"`

Expected: FAIL — unconfirmed user is currently allowed through (no `:confirmable` check in `SignInFlow`).

- [ ] **Step 3: Block unconfirmed users in `SessionsController#create`**

In `app/controllers/authentication/sessions_controller.rb`, find the existing `def create` block. Insert this guard immediately after the `unless result.success?` check and before `reset_session`:

```ruby
      if result.user && !result.user.confirmed?
        session[:unconfirmed_email] = result.user.email
        return redirect_to new_user_session_path(customer_id: current_customer_id)
      end
```

Full updated `create` for reference (replacing the entire method):

```ruby
    # POST /:customer_id/auth/sign_in
    def create
      result = Authentication::SignInFlow.call(
        customer_id: current_customer_id,
        email: sign_in_params[:email],
        password: sign_in_params[:password]
      )

      return render_failure(:missing_credentials)  if result.next_action == :missing_customer
      return render_failure(:invalid_credentials)  unless result.success?

      if result.user && !result.user.confirmed?
        session[:unconfirmed_email] = result.user.email
        return redirect_to new_user_session_path(customer_id: current_customer_id)
      end

      # Mitigate session fixation: rotate the session id across the
      # privilege boundary so any pre-auth session contents are dropped.
      reset_session
      sign_in(resource_name, result.user)
      result.user.update_tracked_fields!(request)
      session[:mfa_verified] = false

      case result.next_action
      when :mfa_required        then redirect_to mfa_session_path(current_customer_id)
      when :mfa_setup_required  then redirect_to mfa_setup_path(current_customer_id)
      else                           redirect_to after_sign_in_path_for(result.user)
      end
    end
```

- [ ] **Step 4: Read the unconfirmed email back in `#new`**

In the same file, replace `def new` with:

```ruby
    # GET /:customer_id/auth/sign_in
    def new
      self.resource = resource_class.new
      @unconfirmed_email = session.delete(:unconfirmed_email)
    end
```

- [ ] **Step 5: Create the partial**

Create `app/views/authentication/sessions/_unconfirmed.html.erb`:

```erb
<div class="mb-6 rounded-lg border border-warning/30 bg-warning-subtle p-4">
  <h3 class="text-subtitle mb-1">Please confirm your email.</h3>
  <p class="text-body-sm mb-3">
    We sent a confirmation link to <strong><%= unconfirmed_email %></strong>.
    Click it to activate your account, then sign in.
  </p>

  <% if auth_settings.signup_enabled? %>
    <%= form_with url: user_confirmation_path(customer_id: current_customer_id),
                  method: :post, local: true, class: "flex items-center gap-2" do |f| %>
      <%= hidden_field_tag "user[email]", unconfirmed_email %>
      <%= f.submit "Resend confirmation", class: "btn-member" %>
    <% end %>
  <% else %>
    <p class="text-body-sm text-text-tertiary">
      Resending confirmation is currently disabled. Contact your administrator.
    </p>
  <% end %>
</div>
```

- [ ] **Step 6: Render the partial in sign-in view**

Edit `app/views/authentication/sessions/new.html.erb`. Immediately after the opening `<%= render Member::AuthShellComponent.new(...) do %>` block (before the `<div class="mb-8">` heading), insert:

```erb
  <% if @unconfirmed_email.present? %>
    <%= render "authentication/sessions/unconfirmed", unconfirmed_email: @unconfirmed_email %>
  <% end %>
```

- [ ] **Step 7: Run the spec**

Run: `bundle exec rspec spec/requests/authentication/sessions_spec.rb -e "unconfirmed user"`

Expected: PASS (2 examples).

- [ ] **Step 8: Commit**

```bash
git add app/controllers/authentication/sessions_controller.rb \
        app/views/authentication/sessions/_unconfirmed.html.erb \
        app/views/authentication/sessions/new.html.erb \
        spec/requests/authentication/sessions_spec.rb
git commit -m "feat(auth): block unconfirmed sign-in; show resend panel on sign-in page

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 12: Hide Sign up / Forgot password links per toggles

**Files:**
- Modify: `app/views/authentication/sessions/new.html.erb`

- [ ] **Step 1: Wrap the "Forgot password?" link in a toggle check**

Edit `app/views/authentication/sessions/new.html.erb`. Find the existing block:

```erb
      <% if current_customer_id.present? %>
        <%= link_to "Forgot password?",
              new_user_password_path(customer_id: current_customer_id),
              class: "text-sm font-medium text-member-accent-text hover:underline" %>
      <% end %>
```

Replace it with:

```erb
      <% if current_customer_id.present? && auth_settings.password_reset_enabled? %>
        <%= link_to "Forgot password?",
              new_user_password_path(customer_id: current_customer_id),
              class: "text-sm font-medium text-member-accent-text hover:underline" %>
      <% end %>
```

- [ ] **Step 2: Wrap the "Create an account" link in a signup toggle check**

In the same file, find:

```erb
  <% if current_customer_id.present? %>
    <p class="mt-6 text-center text-sm text-text-tertiary">
      New here?
      <%= link_to "Create an account", ... %>
    </p>
  <% end %>
```

Replace with:

```erb
  <% if current_customer_id.present? && auth_settings.signup_enabled? %>
    <p class="mt-6 text-center text-sm text-text-tertiary">
      New here?
      <%= link_to "Create an account",
            new_user_registration_path(customer_id: current_customer_id),
            class: "font-medium text-member-accent-text hover:underline" %>
    </p>
  <% end %>
```

- [ ] **Step 3: Smoke check**

Run: `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000 &`

Then: `curl -s http://localhost:3000/81721200/auth/sign_in | grep -E 'Forgot password|Create an account' || echo "links hidden (default toggles)"`

Then kill the background server.

- [ ] **Step 4: Commit**

```bash
git add app/views/authentication/sessions/new.html.erb
git commit -m "feat(auth): hide sign-up/forgot-password links when respective toggle is off

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 13: System spec — admin toggles, public surfaces respond

**Files:**
- Create: `spec/system/admin/settings/user_authentication_spec.rb`

- [ ] **Step 1: Write the spec**

Create `spec/system/admin/settings/user_authentication_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Admin settings — User Authentication", type: :system do
  let!(:customer) { create(:customer) }
  let!(:admin)    { create(:authentication_user, :admin, customer: customer, password: "Password123!") }

  before { driven_by(:rack_test) }

  it "admin can toggle Self sign-up and Forgot password and the public surfaces respond" do
    visit "/#{customer.id}/auth/sign_in"
    fill_in "Email", with: admin.email
    fill_in "Password", with: "Password123!"
    click_button "Sign in"

    visit "/#{customer.id}/admin/settings/modules/authentication"
    expect(page).to have_content("Allow registration")
    expect(page).to have_content("Allow password reset")

    select "Yes", from: "configuration_allow_registration"
    select "No",  from: "configuration_allow_password_reset"
    click_button "Save Configuration"

    fm = FeatureModules::Module.find_by!(key: "authentication")
    cfm = FeatureModules::CustomerAssignment.find_by!(
      customer_id: customer.id, feature_module_id: fm.id
    )
    config = cfm.configuration_json
    expect(config["allow_registration"]).to    eq("true")
    expect(config["allow_password_reset"]).to  eq("false")

    click_link "Sign out" rescue page.driver.submit :delete, "/#{customer.id}/auth/sign_out", {}

    visit "/#{customer.id}/auth/sign_up"
    expect(page).to have_content("Create your account")

    visit "/#{customer.id}/auth/password/new"
    expect(page).to have_content("Password reset is currently disabled")
  end
end
```

(If a `:admin` factory trait does not exist, set up the role via `Role.find_or_create_by!(...)` + `users_roles.create!(...)` inline. Inspect existing admin specs in `spec/requests/admin/settings/modules/authentication/` for the working pattern.)

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/system/admin/settings/user_authentication_spec.rb`

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add spec/system/admin/settings/user_authentication_spec.rb
git commit -m "test(auth): system spec for sign-up/forgot-password toggle end-to-end

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 14: Update stale sign-in / mfa specs that assume immediate sign-in

**Files:**
- Modify: `spec/requests/authentication/sessions_spec.rb`
- Modify: `spec/requests/authentication/mfa_spec.rb`
- Modify: any other spec that creates an `Authentication::User` and expects immediate sign-in without confirmation

- [ ] **Step 1: Identify failing specs**

Run the entire authentication suite:

```bash
bundle exec rspec spec/requests/authentication/ spec/system/authentication/
```

Capture failures. Each "user signs in" assertion that fails because `confirmed_at` is `nil` is a stale spec under the "Stale-test policy" memory.

- [ ] **Step 2: Fix each failing factory call or `let!`**

For each failing test, the simplest fix is creating users with `confirmed_at: Time.current` (these are pre-existing users, not under-test sign-up flows). Search for `create(:authentication_user` in failing files; for tests that DON'T exercise the confirmation flow itself, add `confirmed_at: Time.current`.

Where the existing factory builds users without `confirmed_at`, prefer fixing the factory at `spec/factories/authentication_users.rb` (or wherever it lives) to default `confirmed_at` to `Time.current`, and add a `:unconfirmed` trait that sets it to `nil`. Example:

```ruby
factory :authentication_user, class: "Authentication::User" do
  # ...existing attributes...
  confirmed_at { Time.current }

  trait :unconfirmed do
    confirmed_at { nil }
  end
end
```

Then any spec that wants an unconfirmed user uses `create(:authentication_user, :unconfirmed, ...)`.

- [ ] **Step 3: Re-run the suite**

```bash
bundle exec rspec spec/requests/authentication/ spec/system/authentication/ spec/services/authentication/ spec/models/authentication/
```

Expected: all PASS.

- [ ] **Step 4: Run the full suite to catch fallout elsewhere**

```bash
bundle exec rspec
```

Expected: all PASS. Any failure here is also a stale-test fix; same policy.

- [ ] **Step 5: Commit**

```bash
git add spec/
git commit -m "test: align user factory + stale specs with :confirmable default

Co-Authored-By: Copilot Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 15: Manual QA + final verification

- [ ] **Step 1: Restart the server**

```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

(Run in a dedicated shell. Kill it after the manual checks.)

- [ ] **Step 2: Verify the toggles persist**

Sign in as a customer admin, navigate to `/<cid>/admin/settings/modules/authentication`, flip both toggles, save, refresh the page. Confirm the values are still set.

- [ ] **Step 3: Verify sign-up + confirmation end-to-end**

With `allow_registration = true`:
1. `/<cid>/auth/sign_up` → submit a new email.
2. Check `tail -f log/development.log | grep -E "Sent mail|confirmation_token"` for the confirmation URL.
3. Visit the URL. Confirm redirect to sign-in with "Email confirmed" notice.
4. Sign in. Confirm redirect to `/<cid>/member`.

- [ ] **Step 4: Verify sign-up disabled UX**

Toggle `allow_registration = false` via admin settings. Visit `/<cid>/auth/sign_up` directly. Confirm the disabled page renders. Visit a confirmation URL from step 3 — confirm it now shows the disabled page.

- [ ] **Step 5: Verify forgot-password disabled UX**

Toggle `allow_password_reset = false`. Visit `/<cid>/auth/password/new`. Confirm disabled page. Send a reset (POST). Confirm no email queued.

- [ ] **Step 6: Verify unconfirmed sign-in branch**

Toggle `allow_registration = true`. Sign up a new user. WITHOUT clicking the confirmation link, attempt sign-in with the new credentials. Confirm the "Please confirm your email" panel appears with a working "Resend confirmation" button.

- [ ] **Step 7: Stop the server**

```bash
pkill -f "rails server" || true
```

- [ ] **Step 8: Final commit if any cleanup happened**

```bash
git status
# If anything is uncommitted, address it; otherwise:
git log --oneline -15
```

---

## Self-Review

**Spec coverage:**
- Customer-scoped admin toggle (Self sign-up + Forgot password) → Tasks 1, 13.
- `Authentication::Settings` value object → Task 2.
- `auth_settings` helper → Task 3.
- Devise `:confirmable` columns + backfill → Task 4.
- `:confirmable + :timeoutable` on User; multi-tenant `send_confirmation_instructions` → Task 5.
- Devise initializer settings → Task 6.
- Mailer From unification → Task 7.
- `Authentication::ConfirmationsController` + route + disabled view → Task 8.
- Sign-up disabled UX (200 AuthShell) + role guard → Task 9.
- Forgot-password disabled UX (all 4 actions) → Task 10.
- Unconfirmed-sign-in branch + AuthShell partial → Task 11.
- Hide sign-up / forgot-password links → Task 12.
- System spec → Task 13.
- Stale-test fallout → Task 14.
- Manual QA → Task 15.

All spec sections covered.

**Placeholder scan:** No "TBD", "TODO", "fill in details", or unspecified-error-handling phrases remain. Every step that changes code shows the code.

**Type / signature consistency:**
- `Authentication::Settings.for(customer_id)` — used identically in Tasks 2, 3, 8, 9, 10 (controller bodies, view), 11, 12 (view).
- `auth_settings` helper — defined Task 3, used Tasks 11, 12.
- `signup_enabled?` / `password_reset_enabled?` / `mfa_enabled?` predicate names — consistent across tasks.
- `confirmation_token`, `confirmed_at`, `confirmation_sent_at`, `unconfirmed_email` columns — consistent between Task 4 (migration) and Task 5 (model usage).
- `session[:unconfirmed_email]` — written Task 11 controller, read Task 11 controller `#new`, consumed Task 11 partial.

No drift detected.

**Refinements from spec:**
- Spec called for an `Authentication::FailureApp`. The existing `SessionsController` does not use Warden's failure path (it calls `SignInFlow` directly), so the unconfirmed-email branch is implemented as a guard in `SessionsController#create` rather than a Warden failure handler. Same observable behavior, fewer moving parts.
