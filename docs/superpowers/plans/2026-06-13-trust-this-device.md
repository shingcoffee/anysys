# Trust This Device Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a 2FA user mark their device as trusted at the verification step so subsequent sign-ins from that device skip the TOTP prompt for 30 days.

**Architecture:** A server-side `trusted_devices` row is the source of truth; a signed cookie carries only an opaque token whose SHA-256 digest matches the row. Trust is consumed centrally in `Authentication::SignInFlow` (shared by both sign-in controllers) and auto-revoked via `Authentication::User` callbacks on password or MFA-secret change.

**Tech Stack:** Rails 8.1, Devise, ROTP, RSpec, Tailwind. Multi-tenant via `customer_id`.

---

## File Structure

- Create `db/migrate/<ts>_create_trusted_devices.rb` — `trusted_devices` table.
- Create `app/models/authentication/trusted_device.rb` — model + issue/authenticate API.
- Modify `app/models/authentication/user.rb` — association + revocation callback.
- Modify `app/services/authentication/sign_in_flow.rb` — accept token, return `mfa_verified`.
- Modify `app/controllers/authentication/sessions_controller.rb` — read cookie, set `mfa_verified`.
- Modify `app/controllers/authentication/customer_resolutions_controller.rb` — same.
- Modify `app/controllers/authentication/mfa_sessions_controller.rb` — issue cookie + row on "trust" checkbox.
- Modify `app/views/authentication/mfa_sessions/show.html.erb` — add checkbox.
- Tests under `spec/`.

---

### Task 1: `trusted_devices` migration + model

**Files:**
- Create: `db/migrate/<ts>_create_trusted_devices.rb`
- Create: `app/models/authentication/trusted_device.rb`
- Test: `spec/models/authentication/trusted_device_spec.rb`

- [ ] **Step 1: Write the failing model spec**

```ruby
# spec/models/authentication/trusted_device_spec.rb
require "rails_helper"

RSpec.describe Authentication::TrustedDevice do
  let(:customer) { Customer.create!(id: 81721200, name: "Plat") }
  let(:user) do
    Authentication::User.create!(customer_id: customer.id, email: "a@x.com",
      password: "Password!234", first_name: "A", last_name: "B", confirmed_at: Time.current)
  end

  describe ".issue! / .authenticate" do
    it "issues a row whose digest matches the returned raw token and authenticates it" do
      record, raw = described_class.issue!(user: user, ip: "1.2.3.4", user_agent: "UA")
      expect(raw).to be_present
      expect(record.token_digest).to eq(Digest::SHA256.hexdigest(raw))
      expect(record.token_digest).not_to include(raw)
      expect(record.expires_at).to be > 29.days.from_now
      expect(described_class.authenticate(user: user, raw_token: raw)).to eq(record)
    end

    it "bumps last_used_at on a successful authenticate" do
      record, raw = described_class.issue!(user: user, ip: nil, user_agent: nil)
      record.update_column(:last_used_at, 2.days.ago)
      described_class.authenticate(user: user, raw_token: raw)
      expect(record.reload.last_used_at).to be > 1.minute.ago
    end

    it "returns nil for blank, expired, wrong-user and wrong-tenant tokens" do
      record, raw = described_class.issue!(user: user, ip: nil, user_agent: nil)
      expect(described_class.authenticate(user: user, raw_token: nil)).to be_nil
      expect(described_class.authenticate(user: user, raw_token: "")).to be_nil

      record.update_column(:expires_at, 1.minute.ago)
      expect(described_class.authenticate(user: user, raw_token: raw)).to be_nil
      record.update_column(:expires_at, 10.days.from_now)

      other = Authentication::User.create!(customer_id: customer.id, email: "c@x.com",
        password: "Password!234", first_name: "C", last_name: "D", confirmed_at: Time.current)
      expect(described_class.authenticate(user: other, raw_token: raw)).to be_nil
    end
  end

  describe ".active scope" do
    it "excludes expired rows" do
      live, = described_class.issue!(user: user, ip: nil, user_agent: nil)
      dead, = described_class.issue!(user: user, ip: nil, user_agent: nil)
      dead.update_column(:expires_at, 1.minute.ago)
      expect(described_class.active).to include(live)
      expect(described_class.active).not_to include(dead)
    end
  end
end
```

- [ ] **Step 2: Run it, expect failure**

Run: `bundle exec rspec spec/models/authentication/trusted_device_spec.rb`
Expected: FAIL — uninitialized constant / no table.

- [ ] **Step 3: Write the migration**

```ruby
# db/migrate/<ts>_create_trusted_devices.rb
class CreateTrustedDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :trusted_devices do |t|
      t.integer  :customer_id, null: false
      t.integer  :user_id,     null: false
      t.string   :token_digest, null: false
      t.datetime :expires_at,  null: false
      t.datetime :last_used_at
      t.string   :ip
      t.string   :user_agent
      t.timestamps
    end

    add_index :trusted_devices, :token_digest, unique: true
    add_index :trusted_devices, :customer_id
    add_index :trusted_devices, :user_id
    add_index :trusted_devices, :expires_at
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 4: Write the model**

```ruby
# app/models/authentication/trusted_device.rb
# frozen_string_literal: true

module Authentication
  # Server-side record backing the "trust this device" 2FA bypass. The raw
  # token lives only in a signed browser cookie; we persist its SHA-256 digest
  # so a leaked DB row cannot reconstruct a usable cookie. Scoped per
  # (customer_id, user_id) so a token can never satisfy MFA across tenants.
  class TrustedDevice < ApplicationRecord
    self.table_name = "trusted_devices"

    DEFAULT_TTL = 30.days

    belongs_to :user, class_name: "Authentication::User"

    scope :active, -> { where("expires_at > ?", Time.current) }

    def self.digest_for(raw)
      Digest::SHA256.hexdigest(raw.to_s)
    end

    # Returns [record, raw_token]. The raw token is never persisted.
    def self.issue!(user:, ip:, user_agent:, ttl: DEFAULT_TTL)
      raw = SecureRandom.urlsafe_base64(32)
      record = create!(
        customer_id:  user.customer_id,
        user_id:      user.id,
        token_digest: digest_for(raw),
        expires_at:   ttl.from_now,
        ip:           ip,
        user_agent:   user_agent
      )
      [record, raw]
    end

    # Returns the matching active record for this user, bumping last_used_at;
    # nil if the token is blank, expired, or belongs to another user/tenant.
    def self.authenticate(user:, raw_token:)
      return nil if raw_token.blank? || user.nil?

      record = active.find_by(
        user_id:      user.id,
        customer_id:  user.customer_id,
        token_digest: digest_for(raw_token)
      )
      record&.update_column(:last_used_at, Time.current)
      record
    end
  end
end
```

- [ ] **Step 5: Run the spec, expect PASS**

Run: `bundle exec rspec spec/models/authentication/trusted_device_spec.rb`
Expected: PASS.

---

### Task 2: User association + auto-revocation callback

**Files:**
- Modify: `app/models/authentication/user.rb`
- Test: `spec/models/authentication/user_trusted_device_revocation_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/models/authentication/user_trusted_device_revocation_spec.rb
require "rails_helper"

RSpec.describe Authentication::User, "trusted device revocation" do
  let(:customer) { Customer.create!(id: 81721200, name: "Plat") }
  let(:user) do
    u = described_class.create!(customer_id: customer.id, email: "a@x.com",
      password: "Password!234", first_name: "A", last_name: "B", confirmed_at: Time.current)
    u.generate_otp_secret!; u.enable_mfa!; u
  end

  def trust!
    Authentication::TrustedDevice.issue!(user: user, ip: nil, user_agent: nil)
  end

  it "wipes trusted devices when the password changes" do
    trust!
    user.update!(password: "NewPassword!234")
    expect(user.trusted_devices.count).to eq(0)
  end

  it "wipes trusted devices when MFA is disabled (otp_secret -> nil)" do
    trust!
    user.disable_mfa!
    expect(user.trusted_devices.count).to eq(0)
  end

  it "does NOT wipe when otp_secret rotates to a new (non-nil) value" do
    trust!
    user.generate_otp_secret!
    expect(user.trusted_devices.count).to eq(1)
  end
end
```

- [ ] **Step 2: Run it, expect failure**

Run: `bundle exec rspec spec/models/authentication/user_trusted_device_revocation_spec.rb`
Expected: FAIL — `trusted_devices` undefined / not wiped.

- [ ] **Step 3: Add association + callback to the User model**

Add near the other associations / Devise config block in `app/models/authentication/user.rb`:

```ruby
    has_many :trusted_devices,
             class_name: "Authentication::TrustedDevice",
             foreign_key: :user_id,
             dependent: :delete_all

    after_update :revoke_trusted_devices!,
                 if: -> { saved_change_to_encrypted_password? ||
                          (saved_change_to_otp_secret? && otp_secret.nil?) }
```

And in the 2FA methods region (near `disable_mfa!`):

```ruby
    # Invalidate every "trust this device" record for this user. Fired by the
    # after_update callback on password change/reset and on MFA disable/reset.
    def revoke_trusted_devices!
      trusted_devices.delete_all
    end
```

- [ ] **Step 4: Run the spec, expect PASS**

Run: `bundle exec rspec spec/models/authentication/user_trusted_device_revocation_spec.rb`
Expected: PASS.

---

### Task 3: SignInFlow consumes the trusted-device token

**Files:**
- Modify: `app/services/authentication/sign_in_flow.rb`
- Test: `spec/services/authentication/sign_in_flow_trusted_device_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/authentication/sign_in_flow_trusted_device_spec.rb
require "rails_helper"

RSpec.describe Authentication::SignInFlow, "trusted device" do
  let(:customer) { Customer.create!(id: 81721200, name: "Plat") }
  let!(:user) do
    u = Authentication::User.create!(customer_id: customer.id, email: "a@x.com",
      password: "Password!234", first_name: "A", last_name: "B", confirmed_at: Time.current)
    u.generate_otp_secret!; u.enable_mfa!; u
  end

  def call(token)
    described_class.call(customer_id: customer.id, email: "a@x.com",
      password: "Password!234", trusted_device_token: token)
  end

  it "skips MFA and marks verified when a valid trusted token is presented" do
    _record, raw = Authentication::TrustedDevice.issue!(user: user, ip: nil, user_agent: nil)
    result = call(raw)
    expect(result.next_action).to eq(:authenticated)
    expect(result.mfa_verified).to be(true)
  end

  it "still requires MFA for a missing or invalid token" do
    result = call(nil)
    expect(result.next_action).to eq(:mfa_required)
    expect(result.mfa_verified).to be(false)

    expect(call("garbage").next_action).to eq(:mfa_required)
  end

  it "still requires MFA for an expired token" do
    record, raw = Authentication::TrustedDevice.issue!(user: user, ip: nil, user_agent: nil)
    record.update_column(:expires_at, 1.minute.ago)
    expect(call(raw).next_action).to eq(:mfa_required)
  end
end
```

- [ ] **Step 2: Run it, expect failure**

Run: `bundle exec rspec spec/services/authentication/sign_in_flow_trusted_device_spec.rb`
Expected: FAIL — unknown keyword `trusted_device_token` / no `mfa_verified`.

- [ ] **Step 3: Update SignInFlow**

In `app/services/authentication/sign_in_flow.rb`:

Change the Result struct:
```ruby
    Result = Struct.new(:success?, :user, :next_action, :mfa_verified, keyword_init: true)
```

Change `initialize` to accept the token:
```ruby
    def initialize(customer_id:, email:, password:, trusted_device_token: nil)
      @customer_id = customer_id
      @email = email
      @password = password
      @trusted_device_token = trusted_device_token
    end
```

In `call`, set `mfa_verified` on the success result:
```ruby
      action = post_auth_action(user)
      Result.new(success?: true, user: user, next_action: action,
                 mfa_verified: action == :authenticated)
```

Update `post_auth_action` to honour a valid trusted device:
```ruby
    def post_auth_action(user)
      if user.mfa_required?
        return :authenticated if trusted_device?(user)
        return :mfa_required
      end
      return :mfa_setup_required if user.mfa_configured?

      :authenticated
    end

    def trusted_device?(user)
      Authentication::TrustedDevice.authenticate(
        user: user, raw_token: @trusted_device_token
      ).present?
    end
```

Update `failure` to keep the struct shape valid:
```ruby
    def failure(action, user: nil)
      Result.new(success?: false, user: user, next_action: action, mfa_verified: false)
    end
```

- [ ] **Step 4: Run the spec, expect PASS**

Run: `bundle exec rspec spec/services/authentication/sign_in_flow_trusted_device_spec.rb`
Expected: PASS.

- [ ] **Step 5: Regression-run the existing SignInFlow spec if present**

Run: `bundle exec rspec spec/services/authentication/sign_in_flow_spec.rb`
Expected: PASS (or no such file).

---

### Task 4: Sign-in controllers pass the cookie token + set session

**Files:**
- Modify: `app/controllers/authentication/sessions_controller.rb`
- Modify: `app/controllers/authentication/customer_resolutions_controller.rb`

- [ ] **Step 1: Add a shared cookie reader**

Add to **both** controllers (private method). Read the cookie BEFORE `reset_session`.

```ruby
    # Raw trusted-device token from the signed cookie. The cookie value is
    # "<record_id>:<raw_token>"; we only need the raw token for digest lookup.
    def trusted_device_token
      raw = cookies.signed[:trusted_device]
      return nil if raw.blank?

      raw.to_s.split(":", 2).last.presence
    end
```

- [ ] **Step 2: Pass the token into SignInFlow and set the session from the result**

`sessions_controller.rb#create` — pass token in the call and replace the hardcoded `session[:mfa_verified] = false`:

```ruby
      result = Authentication::SignInFlow.call(
        customer_id: current_customer_id,
        email: sign_in_params[:email],
        password: sign_in_params[:password],
        trusted_device_token: trusted_device_token
      )
```
...after `sign_in`/`update_tracked_fields!`:
```ruby
      session[:mfa_verified] = result.mfa_verified
```

`customer_resolutions_controller.rb#create` — identical edits (token captured before `reset_session`, then `session[:mfa_verified] = result.mfa_verified`).

- [ ] **Step 3: Manual reasoning check (no test step here — covered by request spec in Task 5)**

Confirm: when `next_action == :authenticated` due to trust, `mfa_verified` is `true`, so the subsequent `enforce_mfa!` is satisfied and the user is NOT bounced to `mfa_session`.

- [ ] **Step 4: Boot check**

Run: `bin/rails runner 'puts Authentication::SignInFlow.instance_method(:initialize).parameters.inspect'`
Expected: includes `[:key, :trusted_device_token]`.

---

### Task 5: Issue trust at verification + checkbox UI

**Files:**
- Modify: `app/controllers/authentication/mfa_sessions_controller.rb`
- Modify: `app/views/authentication/mfa_sessions/show.html.erb`
- Test: `spec/requests/authentication/mfa_sessions_trusted_device_spec.rb`

- [ ] **Step 1: Write the failing request spec**

```ruby
# spec/requests/authentication/mfa_sessions_trusted_device_spec.rb
require "rails_helper"

RSpec.describe "MFA session trusted device", type: :request do
  let(:customer) { Customer.create!(id: 81721200, name: "Plat") }
  let!(:user) do
    u = Authentication::User.create!(customer_id: customer.id, email: "a@x.com",
      password: "Password!234", first_name: "A", last_name: "B", confirmed_at: Time.current)
    u.generate_otp_secret!; u.enable_mfa!; u
  end

  before { sign_in user } # Devise test helper; lands pre-MFA-verification

  def valid_code = user.otp.now

  it "creates a trusted device row when the box is checked" do
    expect {
      post mfa_session_path(customer.id), params: { otp_code: valid_code, trust_device: "1" }
    }.to change { user.trusted_devices.count }.by(1)
    expect(response.cookies["trusted_device"]).to be_present
  end

  it "does NOT create a row when the box is unchecked" do
    expect {
      post mfa_session_path(customer.id), params: { otp_code: valid_code }
    }.not_to change { user.trusted_devices.count }
  end

  it "does NOT create a row when the code is invalid" do
    expect {
      post mfa_session_path(customer.id), params: { otp_code: "000000", trust_device: "1" }
    }.not_to change { user.trusted_devices.count }
  end
end
```

> Note for QA: if a Devise request-spec `sign_in` helper is not wired, drive it
> through the real flow: `post user_session_path` then the MFA post. Match the
> existing request-spec auth pattern in the repo.

- [ ] **Step 2: Run it, expect failure**

Run: `bundle exec rspec spec/requests/authentication/mfa_sessions_trusted_device_spec.rb`
Expected: FAIL — no row created / no cookie.

- [ ] **Step 3: Update the controller `create` action**

```ruby
    def create
      if current_user.verify_otp(params[:otp_code])
        session[:mfa_verified] = true
        remember_trusted_device! if params[:trust_device].present?
        redirect_to safe_stored_location || post_verification_path,
                    notice: "Verification successful."
      else
        flash.now[:alert] = "Invalid verification code. Please try again."
        render :show, status: :unprocessable_entity
      end
    end
```

Add private method:

```ruby
    # Persist a trusted-device record and drop a signed cookie so the next
    # sign-in from this browser can skip the TOTP prompt for 30 days.
    def remember_trusted_device!
      record, raw = Authentication::TrustedDevice.issue!(
        user: current_user, ip: request.remote_ip, user_agent: request.user_agent
      )
      cookies.signed[:trusted_device] = {
        value:    "#{record.id}:#{raw}",
        expires:  Authentication::TrustedDevice::DEFAULT_TTL.from_now,
        httponly: true,
        secure:   request.ssl?,
        same_site: :lax
      }
    end
```

- [ ] **Step 4: Add the checkbox to the view**

Insert before the submit button in `mfa_sessions/show.html.erb`:

```erb
    <label class="flex items-center gap-2 text-body-sm select-none cursor-pointer">
      <input type="checkbox" name="trust_device" value="1"
             class="h-4 w-4 rounded border-member-border-warm text-member-accent
                    focus:ring-member-accent">
      <span>Trust this device for 30 days</span>
    </label>
```

- [ ] **Step 5: Run the spec, expect PASS**

Run: `bundle exec rspec spec/requests/authentication/mfa_sessions_trusted_device_spec.rb`
Expected: PASS.

---

### Task 6: Multi-tenant isolation + full regression

**Files:**
- Test: `spec/services/authentication/sign_in_flow_trusted_device_spec.rb` (add a case)

- [ ] **Step 1: Add a cross-tenant isolation example**

```ruby
  it "never lets a token issued for one tenant satisfy MFA for another tenant" do
    other_customer = Customer.create!(id: 96546124, name: "Other")
    other_user = Authentication::User.create!(customer_id: other_customer.id, email: "z@x.com",
      password: "Password!234", first_name: "Z", last_name: "Q", confirmed_at: Time.current)
    other_user.generate_otp_secret!; other_user.enable_mfa!
    _record, raw = Authentication::TrustedDevice.issue!(user: other_user, ip: nil, user_agent: nil)

    # raw belongs to other_user; presenting it for `user` must not skip MFA
    result = described_class.call(customer_id: customer.id, email: "a@x.com",
      password: "Password!234", trusted_device_token: raw)
    expect(result.next_action).to eq(:mfa_required)
  end
```

- [ ] **Step 2: Run the touched specs together**

Run:
```
bundle exec rspec \
  spec/models/authentication/trusted_device_spec.rb \
  spec/models/authentication/user_trusted_device_revocation_spec.rb \
  spec/services/authentication/sign_in_flow_trusted_device_spec.rb \
  spec/requests/authentication/mfa_sessions_trusted_device_spec.rb
```
Expected: all PASS.

- [ ] **Step 3: Rebuild assets + restart dev server (project convention)**

Run:
```
bin/rails tailwindcss:build
rm -f public/assets/.manifest.json
SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

---

## Self-Review

- **Spec coverage:** model (T1), revocation callbacks (T2), SignInFlow consumption (T3), controller wiring (T4), issuance + checkbox (T5), tenant isolation (T6) — all spec sections mapped.
- **Type consistency:** `issue!` returns `[record, raw]`; `authenticate(user:, raw_token:)`; `Result` field `mfa_verified`; cookie key `:trusted_device`; param `trust_device` — consistent across tasks.
- **No placeholders:** all code shown inline.
