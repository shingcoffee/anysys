# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::IssueSignInLink do
  let_it_be(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }

  before { ensure_customer_feature_module(customer, auth_module, status: :active) }

  def enable_signup!
    ensure_customer_feature_module(customer, auth_module, status: :active,
                                   configuration: { allow_registration: "true" }.to_json)
  end

  it "sends a sign-in link to a confirmed user" do
    user = create(:user, customer: customer, email: "back@example.com")

    expect {
      perform_enqueued_jobs { described_class.call(email: "back@example.com") }
    }.to change { ActionMailer::Base.deliveries.size }.by(1)

    user.reload
    expect(user.sign_in_token).to be_present
    expect(user.sign_in_token_sent_at).to be_present
    expect(ActionMailer::Base.deliveries.last.to).to eq(["back@example.com"])
  end

  it "is a no-op for an unknown email" do
    expect {
      perform_enqueued_jobs { described_class.call(email: "nobody@example.com") }
    }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "is a no-op for a blank email" do
    expect {
      perform_enqueued_jobs { described_class.call(email: "  ") }
    }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "matches the address case-insensitively" do
    user = create(:user, customer: customer, email: "mixed@example.com")

    described_class.call(email: "  MiXeD@Example.COM ")

    expect(user.reload.sign_in_token).to be_present
  end

  it "is a no-op when authentication is disabled for the tenant" do
    user = create(:user, customer: customer, email: "off@example.com")
    FeatureModules::CustomerAssignment.where(customer: customer, feature_module: auth_module).delete_all

    expect {
      perform_enqueued_jobs { described_class.call(email: user.email) }
    }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "is a no-op for a deactivated user" do
    user = create(:user, customer: customer, email: "gone@example.com", status: :inactive)

    expect {
      perform_enqueued_jobs { described_class.call(email: user.email) }
    }.not_to change { ActionMailer::Base.deliveries.size }
    expect(user.reload.sign_in_token).to be_nil
  end

  it "does not issue a link when its email lookup raced an identity change" do
    user = create(:user, customer: customer, email: "old@example.com")
    stale = Authentication::User.find(user.id)
    user.update!(email: "new@example.com")
    allow(Authentication::User).to receive(:find_by_normalized_email).with("old@example.com").and_return(stale)

    expect { described_class.call(email: "old@example.com") }
      .not_to have_enqueued_mail(Authentication::SignInLinkMailer, :sign_in_link)
    expect(user.reload.sign_in_token).to be_nil
  end

  # Mail must never be dispatched inline: a synchronous SMTP round trip makes a
  # registered address measurably slower to respond than an unknown one, which
  # is an enumeration oracle even though both render the same check-email page.
  describe "delivery is always enqueued, never inline" do
    it "enqueues the mailer instead of delivering during the call" do
      create(:user, customer: customer, email: "async@example.com")

      expect { described_class.call(email: "async@example.com") }
        .to have_enqueued_mail(Authentication::SignInLinkMailer, :sign_in_link)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  # The unconfirmed branch used to call the INSTANCE method, which bypasses the
  # auth-module + tenant sign-up gate that the class method applies. That let
  # this endpoint mail confirmation instructions for a tenant with sign-up
  # switched off, disagreeing with POST /auth/confirmation.
  describe "unconfirmed users go through the gated confirmation resend" do
    let!(:pending) { create(:user, :unconfirmed, customer: customer, email: "pending@example.com") }

    it "resends confirmation instead of a sign-in link when sign-up is enabled" do
      enable_signup!

      expect {
        perform_enqueued_jobs { described_class.call(email: "pending@example.com") }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(pending.reload.sign_in_token).to be_blank
      expect(ActionMailer::Base.deliveries.last.subject).to match(/confirm/i)
    end

    it "sends nothing when the tenant has sign-up disabled" do
      expect {
        perform_enqueued_jobs { described_class.call(email: "pending@example.com") }
      }.not_to change { ActionMailer::Base.deliveries.size }

      expect(pending.reload.sign_in_token).to be_blank
    end

    it "still resends for an unconfirmed customer admin while the tenant is inactive" do
      admin = create(:user, :admin, :unconfirmed, customer: customer, email: "founder@example.com")

      expect {
        perform_enqueued_jobs { described_class.call(email: admin.email) }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end
  end
end
