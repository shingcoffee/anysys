# Member MFA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Members get MFA off by default at sign-up and can self-enable / self-disable / self-recover from inside the member area; admins keep their current customer-wide enforcement.

**Architecture:** No schema change. Five new files implement the member MFA pages (controller + view + activities/contracts). One new public controller + page handles the email-based recovery flow. One existing helper (`FeatureModules::Authentication::Registration.enforce_mfa!`) gets a one-line member-skip. One existing view (`mfa_sessions/show.html.erb`) gets a "Lost authenticator?" link. Reset tokens are stateless `Rails.application.message_verifier(:member_mfa_reset)` payloads with a 15-minute TTL and an `otp_secret` fingerprint.

**Tech Stack:** Rails 8.1, Devise + Authentication::User, ROTP (TOTP), RQRCode, Reform contracts, ViewComponent, Tailwind, Stimulus, RSpec, FactoryBot, Capybara.

**Spec:** `docs/superpowers/specs/2026-05-25-member-mfa-design.md`

---

## File Inventory

### Create

| Path | Responsibility |
|---|---|
| `app/concepts/member/mfa/contracts/enable.rb` | Reform: validate `code` (presence + 6 digits) for enable POST |
| `app/concepts/member/mfa/contracts/disable.rb` | Reform: validate `code` for disable DELETE |
| `app/concepts/member/mfa/contracts/reset_request.rb` | Reform: validate `email` on the public recovery form |
| `app/concepts/member/mfa/operation/enable.rb` | Operation that verifies the OTP code and flips `enable_mfa!` for a member |
| `app/concepts/member/mfa/operation/disable.rb` | Operation that verifies OTP and runs `disable_mfa!` for a member |
| `app/concepts/member/mfa/operation/request_reset_link.rb` | Mints a signed token and enqueues the recovery email; silent on miss |
| `app/concepts/member/mfa/operation/consume_reset_link.rb` | Verifies signed token, runs `disable_mfa!`, returns user to caller |
| `app/concepts/member/mfa/reset_token.rb` | Token mint/verify helper wrapping `Rails.application.message_verifier(:member_mfa_reset)` with `otp_secret` fingerprint |
| `app/controllers/member/mfa_controller.rb` | `GET/POST setup`, `DELETE` — operates on `current_user` only |
| `app/controllers/authentication/mfa_recoveries_controller.rb` | `new`, `create`, `consume` — public, identical responses for hit/miss |
| `app/mailers/member/mfa_mailer.rb` | `reset_link(user, token)` |
| `app/views/member/mfa/setup.html.erb` | QR + secret + verify form |
| `app/views/authentication/mfa_recoveries/new.html.erb` | Single email field |
| `app/views/authentication/mfa_recoveries/create.html.erb` | Generic confirmation message (rendered for hit and miss) |
| `app/views/member/mfa_mailer/reset_link.html.erb` | HTML email body |
| `app/views/member/mfa_mailer/reset_link.text.erb` | Text email body |
| `spec/concepts/member/mfa/operation/enable_spec.rb` | Operation spec |
| `spec/concepts/member/mfa/operation/disable_spec.rb` | Operation spec |
| `spec/concepts/member/mfa/operation/request_reset_link_spec.rb` | Operation spec |
| `spec/concepts/member/mfa/operation/consume_reset_link_spec.rb` | Operation spec |
| `spec/concepts/member/mfa/reset_token_spec.rb` | Token mint/verify spec |
| `spec/concepts/member/mfa/contracts/enable_spec.rb` | Contract validation spec |
| `spec/concepts/member/mfa/contracts/disable_spec.rb` | Contract validation spec |
| `spec/concepts/member/mfa/contracts/reset_request_spec.rb` | Contract validation spec |
| `spec/requests/member/mfa_spec.rb` | Routes + auth + happy/sad paths |
| `spec/requests/authentication/mfa_recoveries_spec.rb` | Anti-enumeration request specs |
| `spec/mailers/member/mfa_mailer_spec.rb` | Mail body + token presence |
| `spec/system/member/mfa_lifecycle_spec.rb` | End-to-end browser walk-through |

### Modify

| Path | Change |
|---|---|
| `config/routes.rb` | Add `mfa_recovery` resource (public scope) and member `mfa` resource |
| `app/services/feature_modules/authentication/registration.rb` | Skip `enforce_mfa!` for member users (R1) |
| `app/views/member/securities/show.html.erb` | Replace links with member-namespaced URLs |
| `app/controllers/member/securities_controller.rb` | No-op (already exposes `@mfa_enabled`) — verify only |
| `app/views/authentication/mfa_sessions/show.html.erb` | Add "Lost your authenticator?" link |
| `config/locales/en.yml` | Strings under `member.security.mfa.*` and `authentication.mfa_recovery.*` |

---

## Task 1: Stateless reset token helper

**Why first:** Operations 3 and 4 depend on `Member::Mfa::ResetToken`. Building it first lets us unit-test it in isolation.

**Files:**
- Create: `app/concepts/member/mfa/reset_token.rb`
- Test: `spec/concepts/member/mfa/reset_token_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/concepts/member/mfa/reset_token_spec.rb
require "rails_helper"

RSpec.describe Member::Mfa::ResetToken do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, :mfa_configured, customer: customer) }

  describe ".generate and .verify" do
    it "round-trips a token bound to a user and otp_secret" do
      token  = described_class.generate(user)
      result = described_class.verify(token)

      expect(result).to be_success
      expect(result.user).to eq(user)
    end

    it "fails verification when the otp_secret has changed" do
      token = described_class.generate(user)
      user.update!(otp_secret: ROTP::Base32.random)

      result = described_class.verify(token)
      expect(result).not_to be_success
      expect(result.reason).to eq(:fingerprint_mismatch)
    end

    it "fails verification after the TTL has passed" do
      token = described_class.generate(user)

      travel_to(20.minutes.from_now) do
        result = described_class.verify(token)
        expect(result).not_to be_success
        expect(result.reason).to eq(:expired_or_invalid)
      end
    end

    it "fails verification when the token is tampered" do
      token = described_class.generate(user)
      result = described_class.verify(token + "x")

      expect(result).not_to be_success
      expect(result.reason).to eq(:expired_or_invalid)
    end

    it "fails verification when the user is not a member" do
      admin = create(:user, :admin, :mfa_configured, customer: customer)
      token = described_class.generate(admin)

      result = described_class.verify(token)
      expect(result).not_to be_success
      expect(result.reason).to eq(:not_a_member)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rspec spec/concepts/member/mfa/reset_token_spec.rb`
Expected: FAIL with `NameError: uninitialized constant Member::Mfa::ResetToken` (or similar load error).

- [ ] **Step 3: Implement the helper**

```ruby
# app/concepts/member/mfa/reset_token.rb
# frozen_string_literal: true

module Member
  module Mfa
    # Mints/verifies stateless reset-link tokens for the member MFA
    # recovery flow. A token carries (user_id, customer_id, fingerprint),
    # is signed by Rails.application.message_verifier with a 15-minute TTL,
    # and is bound to the current value of user.otp_secret via SHA-256.
    # A successful consume nils the secret, which invalidates the
    # fingerprint of any other outstanding token.
    class ResetToken
      VERIFIER_PURPOSE = :consume
      TTL              = 15.minutes

      Result = Struct.new(:success?, :user, :reason, keyword_init: true)

      def self.generate(user)
        verifier.generate(payload_for(user), purpose: VERIFIER_PURPOSE, expires_in: TTL)
      end

      def self.verify(token)
        payload = verifier.verified(token.to_s, purpose: VERIFIER_PURPOSE)
        return failure(:expired_or_invalid) unless payload.is_a?(Hash)

        user = ::Authentication::User
                 .where(id: payload[:user_id], customer_id: payload[:customer_id])
                 .first
        return failure(:expired_or_invalid) unless user
        return failure(:not_a_member)       unless user.member?
        return failure(:fingerprint_mismatch) unless fingerprint(user.otp_secret) == payload[:fingerprint]

        Result.new(success?: true, user: user, reason: nil)
      end

      def self.fingerprint(otp_secret)
        Digest::SHA256.hexdigest(otp_secret.to_s)
      end

      def self.payload_for(user)
        {
          user_id:     user.id,
          customer_id: user.customer_id,
          fingerprint: fingerprint(user.otp_secret)
        }
      end
      private_class_method :payload_for

      def self.verifier
        Rails.application.message_verifier(:member_mfa_reset)
      end
      private_class_method :verifier

      def self.failure(reason)
        Result.new(success?: false, user: nil, reason: reason)
      end
      private_class_method :failure
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rspec spec/concepts/member/mfa/reset_token_spec.rb`
Expected: PASS (5 examples, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/concepts/member/mfa/reset_token.rb spec/concepts/member/mfa/reset_token_spec.rb
git commit -m "feat(member-mfa): add stateless reset token helper"
```

---

## Task 2: Reform contracts

**Files:**
- Create: `app/concepts/member/mfa/contracts/enable.rb`
- Create: `app/concepts/member/mfa/contracts/disable.rb`
- Create: `app/concepts/member/mfa/contracts/reset_request.rb`
- Test: `spec/concepts/member/mfa/contracts/enable_spec.rb`
- Test: `spec/concepts/member/mfa/contracts/disable_spec.rb`
- Test: `spec/concepts/member/mfa/contracts/reset_request_spec.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/concepts/member/mfa/contracts/enable_spec.rb
require "rails_helper"

RSpec.describe Member::Mfa::Contracts::Enable do
  let(:form) { described_class.new(OpenStruct.new(code: nil)) }

  it "is invalid without a code"            do form.validate(code: "");        expect(form.errors[:code]).to be_present end
  it "is invalid when code is non-digits"   do form.validate(code: "abcdef");  expect(form.errors[:code]).to be_present end
  it "is invalid when code is wrong length" do form.validate(code: "12345");   expect(form.errors[:code]).to be_present end
  it "is valid for 6 digits"                do form.validate(code: "123456");  expect(form.errors[:code]).to be_empty   end
end
```

```ruby
# spec/concepts/member/mfa/contracts/disable_spec.rb
require "rails_helper"

RSpec.describe Member::Mfa::Contracts::Disable do
  let(:form) { described_class.new(OpenStruct.new(code: nil)) }

  it "is invalid without a code" do form.validate(code: ""); expect(form.errors[:code]).to be_present end
  it "is valid for 6 digits"     do form.validate(code: "123456"); expect(form.errors[:code]).to be_empty end
end
```

```ruby
# spec/concepts/member/mfa/contracts/reset_request_spec.rb
require "rails_helper"

RSpec.describe Member::Mfa::Contracts::ResetRequest do
  let(:form) { described_class.new(OpenStruct.new(email: nil)) }

  it "is invalid without email"       do form.validate(email: "");       expect(form.errors[:email]).to be_present end
  it "is invalid for malformed email" do form.validate(email: "not-an-email"); expect(form.errors[:email]).to be_present end
  it "is valid for a real email"      do form.validate(email: "alice@example.com"); expect(form.errors[:email]).to be_empty end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rspec spec/concepts/member/mfa/contracts/`
Expected: load errors for the three contract classes.

- [ ] **Step 3: Implement the contracts**

```ruby
# app/concepts/member/mfa/contracts/enable.rb
# frozen_string_literal: true

module Member
  module Mfa
    module Contracts
      class Enable < Reform::Form
        property :code

        validates :code, presence: true, format: { with: /\A\d{6}\z/, message: :invalid }
      end
    end
  end
end
```

```ruby
# app/concepts/member/mfa/contracts/disable.rb
# frozen_string_literal: true

module Member
  module Mfa
    module Contracts
      class Disable < Reform::Form
        property :code

        validates :code, presence: true, format: { with: /\A\d{6}\z/, message: :invalid }
      end
    end
  end
end
```

```ruby
# app/concepts/member/mfa/contracts/reset_request.rb
# frozen_string_literal: true

module Member
  module Mfa
    module Contracts
      class ResetRequest < Reform::Form
        property :email

        validates :email,
                  presence: true,
                  format:   { with: URI::MailTo::EMAIL_REGEXP }
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rspec spec/concepts/member/mfa/contracts/`
Expected: PASS (8 examples, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/concepts/member/mfa/contracts/ spec/concepts/member/mfa/contracts/
git commit -m "feat(member-mfa): add Reform contracts for enable/disable/reset"
```

---

## Task 3: Enable operation

**Files:**
- Create: `app/concepts/member/mfa/operation/enable.rb`
- Test: `spec/concepts/member/mfa/operation/enable_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/concepts/member/mfa/operation/enable_spec.rb
require "rails_helper"

RSpec.describe Member::Mfa::Operation::Enable do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, :mfa_configured, customer: customer) }
  let(:totp)     { ROTP::TOTP.new(user.otp_secret) }

  it "enables MFA when code is valid and user is a member" do
    result = described_class.call(user: user, code: totp.now)

    expect(result).to be_success
    expect(user.reload.mfa_required?).to be(true)
  end

  it "fails when the code is wrong" do
    result = described_class.call(user: user, code: "000000")

    expect(result).not_to be_success
    expect(user.reload.mfa_required?).to be(false)
  end

  it "rejects non-member users" do
    admin = create(:user, :admin, :mfa_configured, customer: customer)
    totp  = ROTP::TOTP.new(admin.otp_secret)

    result = described_class.call(user: admin, code: totp.now)

    expect(result).not_to be_success
    expect(result.errors[:base]).to include(/member/i)
  end

  it "generates an otp_secret if missing before verifying" do
    user_no_secret = create(:user, :member, customer: customer)
    user_no_secret.update_column(:otp_secret, nil)

    result = described_class.call(user: user_no_secret, code: "000000")
    expect(result).not_to be_success
    expect(user_no_secret.reload.otp_secret).to be_present
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rspec spec/concepts/member/mfa/operation/enable_spec.rb`
Expected: load error for `Member::Mfa::Operation::Enable`.

- [ ] **Step 3: Implement the operation**

```ruby
# app/concepts/member/mfa/operation/enable.rb
# frozen_string_literal: true

module Member
  module Mfa
    module Operation
      class Enable
        Result = Struct.new(:success?, :user, :errors, keyword_init: true)

        def self.call(user:, code:)
          return failure(user, base: ["must be a member"]) unless user&.member?

          user.generate_otp_secret! if user.otp_secret.blank?

          unless user.verify_otp(code)
            return failure(user, code: ["is invalid"])
          end

          user.enable_mfa!
          Result.new(success?: true, user: user, errors: nil)
        end

        def self.failure(user, errors)
          Result.new(success?: false, user: user, errors: errors)
        end
        private_class_method :failure
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rspec spec/concepts/member/mfa/operation/enable_spec.rb`
Expected: PASS (4 examples, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/concepts/member/mfa/operation/enable.rb spec/concepts/member/mfa/operation/enable_spec.rb
git commit -m "feat(member-mfa): add Enable operation"
```

---

## Task 4: Disable operation

**Files:**
- Create: `app/concepts/member/mfa/operation/disable.rb`
- Test: `spec/concepts/member/mfa/operation/disable_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/concepts/member/mfa/operation/disable_spec.rb
require "rails_helper"

RSpec.describe Member::Mfa::Operation::Disable do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, :with_mfa, customer: customer) }
  let(:totp)     { ROTP::TOTP.new(user.otp_secret) }

  it "disables MFA when code is valid" do
    result = described_class.call(user: user, code: totp.now)

    expect(result).to be_success
    user.reload
    expect(user.mfa_required?).to be(false)
    expect(user.otp_secret).to be_nil
  end

  it "fails when the code is wrong and leaves MFA on" do
    result = described_class.call(user: user, code: "000000")

    expect(result).not_to be_success
    expect(user.reload.mfa_required?).to be(true)
  end

  it "fails when MFA is not currently enabled" do
    user.disable_mfa!

    result = described_class.call(user: user, code: "000000")
    expect(result).not_to be_success
    expect(result.errors[:base]).to include(/not enabled/i)
  end

  it "rejects non-member users" do
    admin = create(:user, :admin, :with_mfa, customer: customer)
    totp  = ROTP::TOTP.new(admin.otp_secret)

    result = described_class.call(user: admin, code: totp.now)
    expect(result).not_to be_success
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rspec spec/concepts/member/mfa/operation/disable_spec.rb`
Expected: load error.

- [ ] **Step 3: Implement the operation**

```ruby
# app/concepts/member/mfa/operation/disable.rb
# frozen_string_literal: true

module Member
  module Mfa
    module Operation
      class Disable
        Result = Struct.new(:success?, :user, :errors, keyword_init: true)

        def self.call(user:, code:)
          return failure(user, base: ["must be a member"]) unless user&.member?
          return failure(user, base: ["MFA is not enabled"]) unless user.mfa_required?

          unless user.verify_otp(code)
            return failure(user, code: ["is invalid"])
          end

          user.disable_mfa!
          Result.new(success?: true, user: user, errors: nil)
        end

        def self.failure(user, errors)
          Result.new(success?: false, user: user, errors: errors)
        end
        private_class_method :failure
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rspec spec/concepts/member/mfa/operation/disable_spec.rb`
Expected: PASS (4 examples, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/concepts/member/mfa/operation/disable.rb spec/concepts/member/mfa/operation/disable_spec.rb
git commit -m "feat(member-mfa): add Disable operation"
```

---

## Task 5: Mailer

**Files:**
- Create: `app/mailers/member/mfa_mailer.rb`
- Create: `app/views/member/mfa_mailer/reset_link.html.erb`
- Create: `app/views/member/mfa_mailer/reset_link.text.erb`
- Test: `spec/mailers/member/mfa_mailer_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/mailers/member/mfa_mailer_spec.rb
require "rails_helper"

RSpec.describe Member::MfaMailer do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, :with_mfa, customer: customer) }
  let(:token)    { "signed-token-fixture" }

  describe "#reset_link" do
    let(:mail) { described_class.with(user: user, token: token).reset_link }

    it "is addressed to the user" do
      expect(mail.to).to eq([user.email])
    end

    it "has the expected subject" do
      expect(mail.subject).to match(/two-factor authentication/i)
    end

    it "includes the consume URL with the token" do
      expect(mail.body.encoded).to include(
        "/#{customer.id}/auth/mfa_recovery/consume"
      )
      expect(mail.body.encoded).to include(token)
    end

    it "warns about the 15-minute expiry" do
      expect(mail.body.encoded).to match(/15 minutes/i)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rspec spec/mailers/member/mfa_mailer_spec.rb`
Expected: load error for `Member::MfaMailer`.

- [ ] **Step 3: Implement the mailer**

```ruby
# app/mailers/member/mfa_mailer.rb
# frozen_string_literal: true

module Member
  class MfaMailer < ApplicationMailer
    def reset_link
      @user  = params[:user]
      @token = params[:token]
      @url   = consume_mfa_recovery_url(
        customer_id: @user.customer_id,
        token:       @token,
        host:        default_url_options[:host] || "localhost",
        port:        default_url_options[:port]
      )

      mail(
        to:      @user.email,
        subject: "Reset two-factor authentication for your account"
      )
    end
  end
end
```

```erb
<%# app/views/member/mfa_mailer/reset_link.html.erb %>
<p>Hi <%= @user.display_name %>,</p>

<p>You requested a reset of two-factor authentication for your account.</p>

<p>
  <a href="<%= @url %>" style="display:inline-block;padding:10px 16px;background:#4f46e5;color:#fff;text-decoration:none;border-radius:6px">
    Disable two-factor authentication
  </a>
</p>

<p>This link expires in 15 minutes and can only be used once. If you didn't request this, you can safely ignore this email — your account is unchanged.</p>
```

```erb
<%# app/views/member/mfa_mailer/reset_link.text.erb %>
Hi <%= @user.display_name %>,

You requested a reset of two-factor authentication for your account.

Open this link to disable two-factor authentication:
<%= @url %>

This link expires in 15 minutes and can only be used once. If you didn't request this, you can safely ignore this email — your account is unchanged.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rspec spec/mailers/member/mfa_mailer_spec.rb`
Expected: PASS (4 examples, 0 failures).

NOTE: this depends on the `mfa_recovery` route being registered. Add a temporary stub route now if the route helper is missing:

```ruby
# config/routes.rb — add inside the existing `scope "auth"` block under /:customer_id
resource :mfa_recovery, only: [:new, :create], controller: "authentication/mfa_recoveries" do
  get :consume, on: :collection
end
```

(This route will be re-confirmed in Task 8.)

- [ ] **Step 5: Commit**

```bash
git add app/mailers/member/mfa_mailer.rb \
        app/views/member/mfa_mailer/ \
        spec/mailers/member/mfa_mailer_spec.rb \
        config/routes.rb
git commit -m "feat(member-mfa): add reset-link mailer + recovery routes"
```

---

## Task 6: RequestResetLink operation

**Files:**
- Create: `app/concepts/member/mfa/operation/request_reset_link.rb`
- Test: `spec/concepts/member/mfa/operation/request_reset_link_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/concepts/member/mfa/operation/request_reset_link_spec.rb
require "rails_helper"

RSpec.describe Member::Mfa::Operation::RequestResetLink do
  let(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, :with_mfa, customer: customer, email: "alice@example.com") }
  let(:admin)    { create(:user, :admin, :with_mfa, customer: customer, email: "bob@example.com") }

  before { ActionMailer::Base.deliveries.clear }

  it "delivers a reset email when the email matches a member" do
    expect {
      result = described_class.call(customer_id: customer.id, email: member.email)
      expect(result).to be_success
    }.to change { ActionMailer::Base.deliveries.size }.by(1)

    expect(ActionMailer::Base.deliveries.last.to).to eq([member.email])
  end

  it "is silent (no email) when the address belongs to an admin" do
    expect {
      result = described_class.call(customer_id: customer.id, email: admin.email)
      expect(result).to be_success
    }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "is silent (no email) when the address is unknown" do
    expect {
      result = described_class.call(customer_id: customer.id, email: "ghost@example.com")
      expect(result).to be_success
    }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "matches email case-insensitively and trims whitespace" do
    expect {
      described_class.call(customer_id: customer.id, email: "  ALICE@EXAMPLE.COM ")
    }.to change { ActionMailer::Base.deliveries.size }.by(1)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rspec spec/concepts/member/mfa/operation/request_reset_link_spec.rb`
Expected: load error.

- [ ] **Step 3: Implement the operation**

```ruby
# app/concepts/member/mfa/operation/request_reset_link.rb
# frozen_string_literal: true

module Member
  module Mfa
    module Operation
      class RequestResetLink
        Result = Struct.new(:success?, keyword_init: true)

        def self.call(customer_id:, email:)
          user = lookup(customer_id, email)
          hit  = user.present? && user.member? && user.mfa_configured?

          if hit
            token = Member::Mfa::ResetToken.generate(user)
            Member::MfaMailer.with(user: user, token: token).reset_link.deliver_later
          end

          Rails.logger.info(
            event:       "member_mfa_reset_requested",
            customer_id: customer_id,
            hit:         hit
          )

          Result.new(success?: true)
        end

        def self.lookup(customer_id, email)
          return nil if email.blank?

          ::Authentication::User
            .where(customer_id: customer_id)
            .find_by("LOWER(email) = ?", email.to_s.downcase.strip)
        end
        private_class_method :lookup
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rspec spec/concepts/member/mfa/operation/request_reset_link_spec.rb`
Expected: PASS (4 examples, 0 failures).

NOTE: Tests rely on `deliver_later` enqueuing into ActionMailer's test deliveries. Confirm with: `grep "delivery_method = :test" config/environments/test.rb`. If absent, add `config.action_mailer.delivery_method = :test` and `ActiveJob::Base.queue_adapter = :test` plus `perform_enqueued_jobs` blocks; in this codebase the convention is already `:test`, so `deliver_later` lands in `ActionMailer::Base.deliveries` directly.

- [ ] **Step 5: Commit**

```bash
git add app/concepts/member/mfa/operation/request_reset_link.rb \
        spec/concepts/member/mfa/operation/request_reset_link_spec.rb
git commit -m "feat(member-mfa): add RequestResetLink operation"
```

---

## Task 7: ConsumeResetLink operation

**Files:**
- Create: `app/concepts/member/mfa/operation/consume_reset_link.rb`
- Test: `spec/concepts/member/mfa/operation/consume_reset_link_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/concepts/member/mfa/operation/consume_reset_link_spec.rb
require "rails_helper"

RSpec.describe Member::Mfa::Operation::ConsumeResetLink do
  let(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, :with_mfa, customer: customer) }

  it "disables MFA on a valid token" do
    token  = Member::Mfa::ResetToken.generate(member)
    result = described_class.call(token: token)

    expect(result).to be_success
    expect(result.user).to eq(member)

    member.reload
    expect(member.otp_required_for_login).to be(false)
    expect(member.otp_secret).to be_nil
  end

  it "fails on an expired token" do
    token = Member::Mfa::ResetToken.generate(member)

    travel_to(20.minutes.from_now) do
      result = described_class.call(token: token)
      expect(result).not_to be_success
      expect(member.reload.mfa_required?).to be(true)
    end
  end

  it "fails on a tampered token" do
    token = Member::Mfa::ResetToken.generate(member)

    result = described_class.call(token: token + "x")
    expect(result).not_to be_success
    expect(member.reload.mfa_required?).to be(true)
  end

  it "fails when fingerprint no longer matches (consume after secret rotation)" do
    token = Member::Mfa::ResetToken.generate(member)
    member.update!(otp_secret: ROTP::Base32.random)

    result = described_class.call(token: token)
    expect(result).not_to be_success
  end

  it "rejects an admin-targeted token without modifying the admin's MFA" do
    admin = create(:user, :admin, :with_mfa, customer: customer)
    token = Member::Mfa::ResetToken.generate(admin)

    result = described_class.call(token: token)
    expect(result).not_to be_success
    expect(admin.reload.mfa_required?).to be(true)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rspec spec/concepts/member/mfa/operation/consume_reset_link_spec.rb`
Expected: load error.

- [ ] **Step 3: Implement the operation**

```ruby
# app/concepts/member/mfa/operation/consume_reset_link.rb
# frozen_string_literal: true

module Member
  module Mfa
    module Operation
      class ConsumeResetLink
        Result = Struct.new(:success?, :user, :reason, keyword_init: true)

        def self.call(token:)
          verification = Member::Mfa::ResetToken.verify(token)
          return failure(verification.reason) unless verification.success?

          user = verification.user
          user.disable_mfa!

          Rails.logger.info(
            event:   "member_mfa_reset_consumed",
            user_id: user.id
          )

          Result.new(success?: true, user: user, reason: nil)
        end

        def self.failure(reason)
          Result.new(success?: false, user: nil, reason: reason)
        end
        private_class_method :failure
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rspec spec/concepts/member/mfa/operation/consume_reset_link_spec.rb`
Expected: PASS (5 examples, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add app/concepts/member/mfa/operation/consume_reset_link.rb \
        spec/concepts/member/mfa/operation/consume_reset_link_spec.rb
git commit -m "feat(member-mfa): add ConsumeResetLink operation"
```

---

## Task 8: Routes — add member MFA endpoints

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Edit `config/routes.rb`**

Inside the existing `scope "auth"` block under `/:customer_id` (already added in Task 5), confirm `mfa_recovery` is present:

```ruby
scope "auth" do
  resource :mfa_setup,    only: %i[show create], controller: "authentication/mfa_setups",   path: "mfa/setup"
  resource :mfa_session,  only: %i[show create], controller: "authentication/mfa_sessions", path: "mfa/session"
  resource :mfa,          only: :destroy,        controller: "authentication/mfas",         path: "mfa"
  resource :mfa_recovery, only: %i[new create],  controller: "authentication/mfa_recoveries", path: "mfa_recovery" do
    get :consume, on: :collection
  end
end
```

Inside the existing `namespace :member` block, add the `mfa` resource:

```ruby
namespace :member do
  resource  :dashboard, only: :show, controller: "dashboards", path: ""
  resource  :profile,   only: %i[show edit update]
  resource  :security,  only: :show, controller: "securities" do
    resource :mfa, only: :destroy, controller: "mfa" do
      get  :setup, on: :collection
      post :setup, on: :collection
    end
  end
  resources :surfaces,  only: %i[index show], param: :id, path: ":key"
end
```

- [ ] **Step 2: Verify the routes resolve**

Run:
```bash
bin/rails routes | grep -E "(mfa_recovery|member_security_mfa)"
```

Expected output (paths may print on separate lines; helper names omit the `auth` prefix because `scope` does not namespace helpers):
```
new_mfa_recovery        GET    /:customer_id/auth/mfa_recovery/new(.:format)             authentication/mfa_recoveries#new
mfa_recovery            POST   /:customer_id/auth/mfa_recovery(.:format)                 authentication/mfa_recoveries#create
consume_mfa_recovery    GET    /:customer_id/auth/mfa_recovery/consume(.:format)         authentication/mfa_recoveries#consume
setup_member_security_mfa  GET   /:customer_id/member/security/mfa/setup(.:format)  member/mfa#setup
setup_member_security_mfa  POST  /:customer_id/member/security/mfa/setup(.:format) member/mfa#setup
member_security_mfa        DELETE /:customer_id/member/security/mfa(.:format)      member/mfa#destroy
```

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat(member-mfa): add member-area and recovery routes"
```

---

## Task 9: Member::MfaController + view

**Files:**
- Create: `app/controllers/member/mfa_controller.rb`
- Create: `app/views/member/mfa/setup.html.erb`
- Test: `spec/requests/member/mfa_spec.rb`

- [ ] **Step 1: Write the failing request spec**

```ruby
# spec/requests/member/mfa_spec.rb
require "rails_helper"

RSpec.describe "Member MFA", type: :request do
  let(:customer)   { create(:customer) }
  let(:member)     { create(:user, :member, customer: customer) }
  let(:other_cust) { create(:customer) }
  let(:cid)        { customer.id }

  before do
    auth_module = FeatureModules::Module.find_or_create_by!(key: "authentication") { |m| m.name = "Authentication" }
    [customer, other_cust].each do |c|
      FeatureModules::CustomerAssignment.find_or_create_by!(customer: c, feature_module: auth_module) { |a| a.status = :active }
    end
  end

  describe "GET /:cid/member/security/mfa/setup" do
    context "anonymous" do
      it "redirects to sign-in" do
        get "/#{cid}/member/security/mfa/setup"
        expect(response).to redirect_to("/#{cid}/auth/sign_in")
      end
    end

    context "admin (wrong role)" do
      let(:admin) { create(:user, :admin, customer: customer) }

      it "is rejected by the route gate" do
        sign_in admin
        get "/#{cid}/member/security/mfa/setup"
        expect(response).to redirect_to("/#{cid}")
      end
    end

    context "member" do
      before { sign_in member }

      it "seeds an otp_secret on first visit and renders the QR" do
        expect { get "/#{cid}/member/security/mfa/setup" }
          .to change { member.reload.otp_secret }.from(nil)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("svg")               # QR svg
        expect(response.body).to include(member.otp_secret)   # plain secret
      end

      it "blocks cross-tenant access" do
        get "/#{other_cust.id}/member/security/mfa/setup"
        expect(response).to redirect_to("/#{cid}/admin/dashboard")
      end
    end
  end

  describe "POST /:cid/member/security/mfa/setup" do
    before { sign_in member; member.generate_otp_secret! }
    let(:totp) { ROTP::TOTP.new(member.otp_secret) }

    it "enables MFA on a valid code" do
      post "/#{cid}/member/security/mfa/setup", params: { code: totp.now }
      expect(response).to redirect_to("/#{cid}/member/security")
      expect(member.reload.mfa_required?).to be(true)
    end

    it "re-renders the form on a wrong code" do
      post "/#{cid}/member/security/mfa/setup", params: { code: "000000" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(member.reload.mfa_required?).to be(false)
    end
  end

  describe "DELETE /:cid/member/security/mfa" do
    let(:member) { create(:user, :member, :with_mfa, customer: customer) }
    let(:totp)   { ROTP::TOTP.new(member.otp_secret) }

    before { sign_in member }

    it "disables MFA on a valid code" do
      delete "/#{cid}/member/security/mfa", params: { code: totp.now }
      expect(response).to redirect_to("/#{cid}/member/security")
      expect(member.reload.mfa_required?).to be(false)
    end

    it "leaves MFA on with a wrong code" do
      delete "/#{cid}/member/security/mfa", params: { code: "000000" }
      expect(member.reload.mfa_required?).to be(true)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/member/mfa_spec.rb`
Expected: load error for `Member::MfaController`.

- [ ] **Step 3: Implement the controller**

```ruby
# app/controllers/member/mfa_controller.rb
# frozen_string_literal: true

module Member
  # Member-facing MFA controller. Operates strictly on `current_user`; never
  # accepts a target user_id parameter, which removes a class of cross-user
  # vulnerabilities at the controller layer. Authorization is delegated to
  # Member::BaseController (URL gate enforces `member?`, tenant gate
  # enforces same-customer access).
  class MfaController < BaseController
    before_action :set_no_store_headers, only: :setup

    def setup
      if request.get?
        current_user.generate_otp_secret! if current_user.otp_secret.blank?
        @qr_code = generate_qr_code(current_user.otp_provisioning_uri)
        render :setup
      else
        result = Member::Mfa::Operation::Enable.call(
          user: current_user, code: params[:code]
        )

        if result.success?
          redirect_to member_security_path(current_user.customer_id),
                      notice: t("member.security.mfa.enabled")
        else
          @qr_code = generate_qr_code(current_user.otp_provisioning_uri)
          flash.now[:alert] = t("member.security.mfa.invalid_code")
          render :setup, status: :unprocessable_entity
        end
      end
    end

    def destroy
      result = Member::Mfa::Operation::Disable.call(
        user: current_user, code: params[:code]
      )

      if result.success?
        redirect_to member_security_path(current_user.customer_id),
                    notice: t("member.security.mfa.disabled")
      else
        redirect_to member_security_path(current_user.customer_id),
                    alert:  t("member.security.mfa.invalid_code")
      end
    end

    private

    def set_no_store_headers
      response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, private"
      response.headers["Pragma"]        = "no-cache"
    end

    def generate_qr_code(uri)
      return nil unless uri

      RQRCode::QRCode.new(uri).as_svg(
        color: "000", shape_rendering: "crispEdges",
        module_size: 4, standalone: true, use_path: true
      )
    end
  end
end
```

- [ ] **Step 4: Implement the setup view**

```erb
<%# app/views/member/mfa/setup.html.erb %>
<% content_for :title, "Two-factor authentication — Anysys" %>
<% content_for :member_nav, "security" %>

<%= render Member::PageHeaderComponent.new(
      title:    "Set up two-factor authentication",
      subtitle: "Scan the QR code with your authenticator app, then enter the 6-digit code to enable."
    ) %>

<div class="space-y-4">
  <%= render Member::PageSectionComponent.new(title: "1. Scan the QR code") do %>
    <div class="flex flex-col items-center gap-4">
      <% if @qr_code %>
        <div class="rounded-lg border border-gray-200 bg-white p-4 inline-block"><%= @qr_code.html_safe %></div>
      <% end %>
      <p class="text-body-sm text-gray-600">Or enter this secret manually:</p>
      <code class="font-mono text-sm bg-gray-100 px-3 py-2 rounded select-all"><%= current_user.otp_secret %></code>
    </div>
  <% end %>

  <%= render Member::PageSectionComponent.new(title: "2. Enter the 6-digit code") do %>
    <%= form_tag setup_member_security_mfa_path(current_user.customer_id),
                 method: :post, class: "space-y-4" do %>
      <div>
        <label for="code" class="block text-sm font-medium text-gray-700 mb-1">Verification code</label>
        <input type="text" name="code" id="code"
               autofocus autocomplete="one-time-code" inputmode="numeric"
               pattern="[0-9]*" maxlength="6"
               class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-4 py-3 text-center tracking-widest text-lg font-mono">
      </div>
      <div class="flex justify-end gap-2">
        <%= link_to "Cancel", member_security_path(current_user.customer_id),
              class: "btn btn-ghost" %>
        <button type="submit" class="btn-member">Verify and enable</button>
      </div>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 5: Add the i18n strings**

Open `config/locales/en.yml` and add (under `en:`):

```yaml
en:
  member:
    security:
      mfa:
        enabled:       "Two-factor authentication has been enabled."
        disabled:      "Two-factor authentication has been disabled."
        invalid_code:  "Invalid verification code. Please try again."
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rspec spec/requests/member/mfa_spec.rb`
Expected: PASS (7 examples, 0 failures).

- [ ] **Step 7: Commit**

```bash
git add app/controllers/member/mfa_controller.rb \
        app/views/member/mfa/setup.html.erb \
        config/locales/en.yml \
        spec/requests/member/mfa_spec.rb
git commit -m "feat(member-mfa): add member self-service enable/disable"
```

---

## Task 10: Update the security page to use member-namespaced URLs

**Files:**
- Modify: `app/views/member/securities/show.html.erb`

- [ ] **Step 1: Replace the two MFA links/buttons**

Find this block (around line 36-46):

```erb
      <% if @mfa_enabled %>
        <%= button_to "Disable 2FA",
              "/#{current_user.customer_id}/auth/mfa",
              method: :delete,
              class: "btn btn-ghost text-danger",
              data: { confirm: "Disable two-factor authentication for your account?" } %>
      <% else %>
        <%= link_to "Set up 2FA",
              "/#{current_user.customer_id}/auth/mfa/setup",
              class: "btn-member" %>
      <% end %>
```

Replace with:

```erb
      <% if @mfa_enabled %>
        <details class="ml-auto">
          <summary class="btn btn-ghost text-danger cursor-pointer list-none">Disable 2FA</summary>
          <%= form_tag member_security_mfa_path(current_user.customer_id),
                       method: :delete, class: "mt-3 flex items-end gap-2" do %>
            <div class="flex-1">
              <label for="code" class="block text-sm font-medium text-gray-700 mb-1">Verification code</label>
              <input type="text" name="code" id="code"
                     autocomplete="one-time-code" inputmode="numeric"
                     pattern="[0-9]*" maxlength="6"
                     class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-3 py-2 text-center font-mono">
            </div>
            <button type="submit" class="btn btn-danger">Confirm disable</button>
          <% end %>
        </details>
      <% else %>
        <%= link_to "Set up 2FA",
              setup_member_security_mfa_path(current_user.customer_id),
              class: "btn-member" %>
      <% end %>
```

- [ ] **Step 2: Run the existing security request specs**

Run: `bin/rspec spec/requests/member/`
Expected: PASS (no regressions). If `securities` has its own request spec that locks the old URL, update it to expect the new path.

- [ ] **Step 3: Commit**

```bash
git add app/views/member/securities/show.html.erb
git commit -m "feat(member-mfa): point security page at member-namespaced MFA"
```

---

## Task 11: MfaRecoveriesController + views (anti-enumeration)

**Files:**
- Create: `app/controllers/authentication/mfa_recoveries_controller.rb`
- Create: `app/views/authentication/mfa_recoveries/new.html.erb`
- Create: `app/views/authentication/mfa_recoveries/create.html.erb`
- Test: `spec/requests/authentication/mfa_recoveries_spec.rb`

- [ ] **Step 1: Write the failing request spec**

```ruby
# spec/requests/authentication/mfa_recoveries_spec.rb
require "rails_helper"

RSpec.describe "MFA Recovery", type: :request do
  let(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, :with_mfa, customer: customer, email: "alice@example.com") }
  let(:admin)    { create(:user, :admin, :with_mfa, customer: customer, email: "bob@example.com") }
  let(:cid)      { customer.id }

  describe "GET /:cid/auth/mfa_recovery/new" do
    it "is publicly accessible" do
      get "/#{cid}/auth/mfa_recovery/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("email")
    end
  end

  describe "POST /:cid/auth/mfa_recovery" do
    before { ActionMailer::Base.deliveries.clear }

    it "renders the same generic confirmation regardless of email outcome" do
      post "/#{cid}/auth/mfa_recovery", params: { email: member.email }
      member_body = response.body

      ActionMailer::Base.deliveries.clear
      post "/#{cid}/auth/mfa_recovery", params: { email: admin.email }
      admin_body = response.body

      ActionMailer::Base.deliveries.clear
      post "/#{cid}/auth/mfa_recovery", params: { email: "ghost@example.com" }
      missing_body = response.body

      expect(member_body).to eq(admin_body)
      expect(member_body).to eq(missing_body)
    end

    it "delivers an email only for member matches" do
      expect { post "/#{cid}/auth/mfa_recovery", params: { email: member.email } }
        .to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    it "does not email admins" do
      expect { post "/#{cid}/auth/mfa_recovery", params: { email: admin.email } }
        .not_to change { ActionMailer::Base.deliveries.size }
    end
  end

  describe "GET /:cid/auth/mfa_recovery/consume" do
    it "disables MFA on a valid token and redirects to sign-in" do
      token = Member::Mfa::ResetToken.generate(member)

      get "/#{cid}/auth/mfa_recovery/consume", params: { token: token }
      expect(response).to redirect_to("/#{cid}/auth/sign_in")
      expect(flash[:notice]).to match(/disabled/i)
      expect(member.reload.mfa_required?).to be(false)
    end

    it "shows a generic flash on an admin-targeted token without modifying the admin" do
      token = Member::Mfa::ResetToken.generate(admin)

      get "/#{cid}/auth/mfa_recovery/consume", params: { token: token }
      expect(response).to redirect_to("/#{cid}/auth/sign_in")
      expect(flash[:alert]).to match(/invalid|expired/i)
      expect(admin.reload.mfa_required?).to be(true)
    end

    it "shows a generic flash on an expired token" do
      token = Member::Mfa::ResetToken.generate(member)

      travel_to(20.minutes.from_now) do
        get "/#{cid}/auth/mfa_recovery/consume", params: { token: token }
        expect(flash[:alert]).to match(/invalid|expired/i)
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/authentication/mfa_recoveries_spec.rb`
Expected: routing/load errors.

- [ ] **Step 3: Implement the controller**

```ruby
# app/controllers/authentication/mfa_recoveries_controller.rb
# frozen_string_literal: true

module Authentication
  # Public endpoint that lets a member who lost their authenticator request
  # an email link that disables their MFA. Identical responses for hit/miss
  # to prevent email enumeration. Member-only enforcement lives in the
  # operations, NOT here.
  class MfaRecoveriesController < ApplicationController
    layout "auth"

    def new
    end

    def create
      contract = Member::Mfa::Contracts::ResetRequest.new(OpenStruct.new(email: nil))

      if contract.validate(email: params[:email])
        Member::Mfa::Operation::RequestResetLink.call(
          customer_id: current_customer_id, email: params[:email]
        )
      end

      # Always render the same generic page, even on contract failure.
      render :create
    end

    def consume
      result = Member::Mfa::Operation::ConsumeResetLink.call(token: params[:token])

      reset_session
      sign_out(:user) if user_signed_in?

      if result.success?
        redirect_to new_user_session_path(customer_id: current_customer_id),
                    notice: t("authentication.mfa_recovery.consumed")
      else
        redirect_to new_user_session_path(customer_id: current_customer_id),
                    alert:  t("authentication.mfa_recovery.invalid")
      end
    end
  end
end
```

- [ ] **Step 4: Implement the views**

```erb
<%# app/views/authentication/mfa_recoveries/new.html.erb %>
<%= render layout: "authentication/shared/auth_card",
           locals: { title: "Recover access",
                     subtitle: "Lost your authenticator? Enter your email and we'll send you a one-time reset link.",
                     icon_path: "M16 12a4 4 0 11-8 0 4 4 0 018 0zm6 0c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10z" } do %>

  <%= form_tag mfa_recovery_path(current_customer_id), method: :post, class: "space-y-6" do %>
    <div>
      <label for="email" class="block text-sm font-medium text-gray-700 mb-1">Email</label>
      <input type="email" name="email" id="email" autofocus autocomplete="email"
             class="block w-full rounded-lg border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 text-sm px-4 py-3">
    </div>
    <button type="submit" class="btn btn-primary w-full">Send reset link</button>
  <% end %>

  <div class="mt-6 text-center">
    <%= link_to "Back to sign-in", new_user_session_path(customer_id: current_customer_id),
          class: "text-sm text-gray-500 hover:text-gray-700" %>
  </div>
<% end %>
```

```erb
<%# app/views/authentication/mfa_recoveries/create.html.erb %>
<%= render layout: "authentication/shared/auth_card",
           locals: { title: "Check your email",
                     subtitle: "If that email belongs to a member account with two-factor authentication enabled, we just sent a reset link. The link expires in 15 minutes.",
                     icon_path: "M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" } do %>

  <div class="mt-6 text-center">
    <%= link_to "Back to sign-in", new_user_session_path(customer_id: current_customer_id),
          class: "text-sm text-gray-500 hover:text-gray-700" %>
  </div>
<% end %>
```

- [ ] **Step 5: Add the i18n strings**

Append to `config/locales/en.yml`:

```yaml
  authentication:
    mfa_recovery:
      consumed: "Two-factor authentication has been disabled. Please sign in."
      invalid:  "This reset link is invalid or has expired."
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rspec spec/requests/authentication/mfa_recoveries_spec.rb`
Expected: PASS (7 examples, 0 failures).

- [ ] **Step 7: Commit**

```bash
git add app/controllers/authentication/mfa_recoveries_controller.rb \
        app/views/authentication/mfa_recoveries/ \
        config/locales/en.yml \
        spec/requests/authentication/mfa_recoveries_spec.rb
git commit -m "feat(member-mfa): add public recovery flow with anti-enumeration"
```

---

## Task 12: Add "Lost your authenticator?" link to the MFA challenge page

**Files:**
- Modify: `app/views/authentication/mfa_sessions/show.html.erb`

- [ ] **Step 1: Add the link below the existing sign-out link**

Replace the bottom block (lines 23-27):

```erb
  <div class="mt-6 text-center">
    <%= link_to "Sign out", destroy_user_session_path(customer_id: current_customer_id),
          data: { turbo_method: :delete },
          class: "text-sm text-gray-500 hover:text-gray-700" %>
  </div>
```

With:

```erb
  <div class="mt-6 text-center space-y-2">
    <%= link_to "Lost your authenticator?", new_mfa_recovery_path(current_customer_id),
          class: "block text-sm text-indigo-600 hover:text-indigo-800" %>
    <%= link_to "Sign out", destroy_user_session_path(customer_id: current_customer_id),
          data: { turbo_method: :delete },
          class: "block text-sm text-gray-500 hover:text-gray-700" %>
  </div>
```

- [ ] **Step 2: Run the existing mfa_sessions request spec for regressions**

Run: `bin/rspec spec/requests/authentication 2>/dev/null || bin/rspec spec/requests/`
Expected: PASS or no relevant failures.

- [ ] **Step 3: Commit**

```bash
git add app/views/authentication/mfa_sessions/show.html.erb
git commit -m "feat(member-mfa): expose recovery link on the MFA challenge page"
```

---

## Task 13: Skip enforce_mfa! for members (R1 — the core behavior flip)

**Files:**
- Modify: `app/services/feature_modules/authentication/registration.rb`
- Update: any existing spec asserting customer-wide MFA forces members (per the stale-test policy)

- [ ] **Step 1: Find specs that assert "customer-wide MFA forces a member"**

Run: `rtk grep -rln "enforce_mfa\|mfa_enabled" spec/ | head`

Read each match. Any spec asserting that a member is redirected to MFA setup when the customer-level setting is on is now stale — it must be rewritten to assert the **opposite** (members are NOT forced) and that admins ARE still forced.

- [ ] **Step 2: Add new test asserting the member-skip**

Add to whichever existing spec covers `enforce_mfa!` (likely `spec/services/feature_modules/authentication/registration_spec.rb` or a request spec around the admin dashboard). If none exists, create:

```ruby
# spec/services/feature_modules/authentication/registration_enforce_mfa_spec.rb
require "rails_helper"

RSpec.describe FeatureModules::Authentication::Registration, ".enforce_mfa!" do
  let(:customer) { create(:customer) }

  before do
    auth_module = FeatureModules::Module.find_or_create_by!(key: "authentication") { |m| m.name = "Authentication" }
    assignment = FeatureModules::CustomerAssignment.find_or_create_by!(
      customer: customer, feature_module: auth_module
    ) { |a| a.status = :active }
    assignment.update!(configuration: { mfa_enabled: true })
  end

  context "with customer-wide MFA on" do
    it "does NOT force a member into MFA setup" do
      member = create(:user, :member, customer: customer)
      sign_in member

      get "/#{customer.id}/member"
      expect(response).to have_http_status(:ok)
    end

    it "DOES force an admin into MFA setup" do
      admin = create(:user, :admin, customer: customer)
      sign_in admin

      get "/#{customer.id}/admin/dashboard"
      expect(response).to redirect_to("/#{customer.id}/auth/mfa/setup")
    end
  end
end
```

- [ ] **Step 3: Run the new spec to verify it fails on the member case**

Run: `bin/rspec spec/services/feature_modules/authentication/registration_enforce_mfa_spec.rb`
Expected: the member case FAILS (currently the helper redirects). Admin case may pass.

- [ ] **Step 4: Make the one-line code change**

In `app/services/feature_modules/authentication/registration.rb`, find:

```ruby
      def self.enforce_mfa!(controller)
        return unless controller.user_signed_in?
        return unless mfa_required_for?(controller.current_customer_id)

        if controller.current_user.mfa_configured?
          return if controller.session[:mfa_verified]
          ...
```

Replace with:

```ruby
      def self.enforce_mfa!(controller)
        return unless controller.user_signed_in?
        # Members are always opt-in for MFA. Customer-wide enforcement
        # applies only to admins/owners; members manage MFA themselves
        # under /:cid/member/security/mfa.
        return if controller.current_user.member?
        return unless mfa_required_for?(controller.current_customer_id)

        if controller.current_user.mfa_configured?
          return if controller.session[:mfa_verified]
          ...
```

- [ ] **Step 5: Re-run the spec**

Run: `bin/rspec spec/services/feature_modules/authentication/registration_enforce_mfa_spec.rb`
Expected: PASS (2 examples, 0 failures).

- [ ] **Step 6: Run the full request-spec sweep to find other stale assertions**

Run: `bin/rspec spec/requests spec/services`
Expected: any failure here is a stale spec to rewrite per the stale-test policy. Update each to assert the new behavior — do NOT revert the production change.

- [ ] **Step 7: Commit**

```bash
git add app/services/feature_modules/authentication/registration.rb \
        spec/services/feature_modules/authentication/registration_enforce_mfa_spec.rb \
        $(git diff --name-only spec/)
git commit -m "feat(member-mfa): skip customer-wide MFA enforcement for members"
```

---

## Task 14: System spec — end-to-end member MFA lifecycle

**Files:**
- Test: `spec/system/member/mfa_lifecycle_spec.rb`

- [ ] **Step 1: Write the system spec**

```ruby
# spec/system/member/mfa_lifecycle_spec.rb
require "rails_helper"

RSpec.describe "Member MFA lifecycle", type: :system do
  let(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, customer: customer, password: "password123") }
  let(:cid)      { customer.id }

  before do
    auth_module = FeatureModules::Module.find_or_create_by!(key: "authentication") { |m| m.name = "Authentication" }
    FeatureModules::CustomerAssignment.find_or_create_by!(
      customer: customer, feature_module: auth_module
    ) { |a| a.status = :active }
    ActionMailer::Base.deliveries.clear
  end

  it "lets a member enable MFA, sign in with it, recover via email, and sign in without it" do
    # 1. Sign in fresh; MFA off by default
    visit "/#{cid}/auth/sign_in"
    fill_in "Email",    with: member.email
    fill_in "Password", with: "password123"
    click_button "Sign in"

    expect(page).to have_current_path("/#{cid}/member")

    # 2. Visit security page; see "off"
    visit "/#{cid}/member/security"
    expect(page).to have_content("2FA is off")
    click_link "Set up 2FA"

    # 3. Enable
    expect(page).to have_current_path("/#{cid}/member/security/mfa/setup")
    member.reload
    totp = ROTP::TOTP.new(member.otp_secret)
    fill_in "Verification code", with: totp.now
    click_button "Verify and enable"

    expect(page).to have_current_path("/#{cid}/member/security")
    expect(page).to have_content("2FA is on")

    # 4. Sign out, sign back in -> MFA challenge
    click_link "Sign out" rescue visit "/#{cid}/auth/sign_out"
    visit "/#{cid}/auth/sign_in"
    fill_in "Email",    with: member.email
    fill_in "Password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path("/#{cid}/auth/mfa/session")

    # 5. Click "Lost your authenticator?" -> request reset
    click_link "Lost your authenticator?"
    fill_in "Email", with: member.email
    click_button "Send reset link"
    expect(page).to have_content(/check your email/i)

    # 6. Read the email, click the link
    mail = ActionMailer::Base.deliveries.last
    expect(mail).not_to be_nil
    consume_url = mail.body.encoded[/(\/#{cid}\/auth\/mfa_recovery\/consume\?token=[^"\s]+)/, 1]
    expect(consume_url).to be_present

    visit consume_url
    expect(page).to have_current_path("/#{cid}/auth/sign_in")
    expect(page).to have_content(/disabled/i)

    # 7. Sign in normally — no MFA challenge
    fill_in "Email",    with: member.email
    fill_in "Password", with: "password123"
    click_button "Sign in"
    expect(page).to have_current_path("/#{cid}/member")
  end
end
```

- [ ] **Step 2: Run the system spec**

Run: `bin/rspec spec/system/member/mfa_lifecycle_spec.rb`
Expected: PASS (1 example, 0 failures).

- [ ] **Step 3: Commit**

```bash
git add spec/system/member/mfa_lifecycle_spec.rb
git commit -m "test(member-mfa): end-to-end lifecycle system spec"
```

---

## Task 15: Full sweep + dev-server smoke test

**Files:** none (verification only)

- [ ] **Step 1: Run the full RSpec suite for the touched areas**

Run:
```bash
bin/rspec spec/concepts/member/mfa \
          spec/requests/member \
          spec/requests/authentication \
          spec/mailers/member \
          spec/services/feature_modules/authentication \
          spec/system/member/mfa_lifecycle_spec.rb
```

Expected: ALL PASS, no pending.

- [ ] **Step 2: Restart the dev server with the manifest cleared**

Run:
```bash
rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000
```

(Run in background; the next step browses against it.)

- [ ] **Step 3: Smoke-hit the new pages**

In another terminal:
```bash
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3000/$(rails runner -e development 'print Customer.first.id' 2>/dev/null)/member/security/mfa/setup"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3000/$(rails runner -e development 'print Customer.first.id' 2>/dev/null)/auth/mfa_recovery/new"
```

Expected: `200 200` (or `302` for routes that need a signed-in member depending on `SKIP_AUTH` behavior — verify in browser instead).

- [ ] **Step 4: No commit needed**

This is a verification step. If anything regressed, fix it in a new task before merging.

---

## Self-Review Notes

After writing this plan, I checked:

- **Spec coverage** — every section of the spec maps to a task: R1 → Task 13; R2 → Tasks 8–10; R3 → Tasks 5–7, 11–12; data/tokens → Task 1; contracts → Task 2; operations → Tasks 3–4, 6–7; controllers → Tasks 9, 11; routes → Task 8; UI → Tasks 9–12; testing pyramid → Tasks 1–14; observability log events → embedded in Tasks 6–7.
- **Placeholder scan** — no "TBD", "TODO", or "fill in details". All steps include the actual code.
- **Type/name consistency** — `Member::Mfa::ResetToken.generate/verify`, `ResetToken::Result(success?, user, reason)`, `Operation::Enable.call(user:, code:)`, `Operation::Disable.call(user:, code:)`, `Operation::RequestResetLink.call(customer_id:, email:)`, `Operation::ConsumeResetLink.call(token:)`, `Member::MfaMailer.with(user:, token:).reset_link.deliver_later`, route names `setup_member_security_mfa_path` / `member_security_mfa_path` / `mfa_recovery_path` / `new_mfa_recovery_path` / `consume_mfa_recovery_url` (no `auth_` prefix because `scope` does not namespace helper names) — all consistent across tasks.
- **Stale-test policy** — Task 13 explicitly searches for and rewrites stale specs that asserted customer-wide MFA forces members.
