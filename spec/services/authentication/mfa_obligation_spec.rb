# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::MfaObligation do
  subject(:obligation) { described_class.for(user: user, verified: verified) }

  let(:customer) { create(:customer) }
  let(:auth_module) { ::FeatureModules::Module.find_by!(key: "authentication") }
  let(:verified) { false }

  def set_tenant_mfa(enabled)
    ensure_customer_feature_module(
      customer, auth_module,
      status: :active,
      configuration: { "mfa_enabled" => enabled }.to_json
    )
  end

  describe "no user" do
    let(:user) { nil }

    it "owes nothing" do
      expect(described_class.for(user: nil, verified: false)).to eq(described_class::NONE)
    end
  end

  describe "an enrolled user whose MFA is enforced" do
    let(:user) { create(:user, :admin, :with_mfa, customer: customer) }

    before { set_tenant_mfa(true) }

    it "owes a verification when the session has not presented a code" do
      expect(obligation).to eq(described_class::VERIFY)
    end

    context "when the session has already verified against the current secret" do
      let(:verified) { true }

      it "owes nothing" do
        expect(obligation).to eq(described_class::NONE)
      end
    end
  end

  describe "a user who has a secret but is not yet enforced" do
    let(:user) { create(:user, :admin, customer: customer) }

    before do
      set_tenant_mfa(false)
      user.generate_otp_secret!
      user.update!(otp_required_for_login: false)
    end

    it "owes an enrolment so the half-finished setup is completed" do
      expect(obligation).to eq(described_class::ENROLL)
    end

    # This is the bypass the service exists to close. A session established
    # before the secret was planted (or before the tenant switched MFA on)
    # carried verified = true for its whole life, and the old gate
    # short-circuited on it — so the mandate never reached anyone already
    # signed in. An enrolment is only satisfiable by enrolling.
    context "when the session carries a stale verified flag" do
      let(:verified) { true }

      it "still owes the enrolment" do
        expect(obligation).to eq(described_class::ENROLL)
      end
    end
  end

  describe "tenant-wide enforcement" do
    before { set_tenant_mfa(true) }

    it "binds an admin with no secret to enrol" do
      user = create(:user, :admin, customer: customer)
      expect(described_class.for(user: user, verified: false)).to eq(described_class::ENROLL)
    end

    it "binds the platform owner with no secret to enrol" do
      owner = find_or_create_platform_owner
      ensure_customer_feature_module(
        owner.customer, auth_module,
        status: :active,
        configuration: { "mfa_enabled" => true }.to_json
      )

      expect(described_class.for(user: owner, verified: false)).to eq(described_class::ENROLL)
    end

    # Members manage their own second factor under /:cid/member/security/mfa;
    # a tenant mandate aimed at staff must not lock self-signed-up members out.
    it "leaves a plain member opt-in" do
      user = create(:user, :member, customer: customer)
      expect(described_class.for(user: user, verified: false)).to eq(described_class::NONE)
    end
  end

  describe "when the tenant does not enforce MFA" do
    let(:user) { create(:user, :admin, customer: customer) }

    before { set_tenant_mfa(false) }

    it "owes nothing for a user with no secret" do
      expect(obligation).to eq(described_class::NONE)
    end
  end
end
