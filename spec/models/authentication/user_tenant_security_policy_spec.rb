# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication::User tenant security policy", type: :model do
  let(:customer) { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:user) { create(:user, :member, customer: customer, password: "Password123!") }
  let(:other_user) { create(:user, :member, customer: other_customer, password: "Password123!") }
  let(:auth_module) { FeatureModules::Module.find_by!(key: "authentication") }

  def configure_policy(tenant, timeout:, attempts:)
    ensure_customer_feature_module(tenant, auth_module, status: :active,
                                   configuration: { "session_timeout" => timeout, "max_login_attempts" => attempts }.to_json)
  end

  before do
    configure_policy(customer, timeout: 2, attempts: 2)
    configure_policy(other_customer, timeout: 8, attempts: 5)
  end

  it "applies Devise timedout? using the account's own tenant without changing global policy" do
    class_timeout = Authentication::User.timeout_in
    global_timeout = Devise.timeout_in

    expect(user.timedout?(3.minutes.ago)).to be(true)
    expect(other_user.timedout?(3.minutes.ago)).to be(false)
    Current.set(customer: other_customer) { expect(user.timeout_in).to eq(2.minutes) }
    expect(Authentication::User.timeout_in).to eq(class_timeout)
    expect(Devise.timeout_in).to eq(global_timeout)
  end

  it "re-reads a changed tenant policy for an already loaded user" do
    expect(user.maximum_attempts).to eq(2)
    expect(user.timeout_in).to eq(2.minutes)

    configure_policy(customer, timeout: 4, attempts: 3)

    expect(user.maximum_attempts).to eq(3)
    expect(user.timeout_in).to eq(4.minutes)
    expect(other_user.maximum_attempts).to eq(5)
  end

  it "locks at each tenant's actual threshold through PasswordVerification and preserves other tenants" do
    class_limit = Authentication::User.maximum_attempts
    global_limit = Devise.maximum_attempts

    2.times do
      expect(Authentication::PasswordVerification.authenticate(user: user, password: "wrong")).to be_nil
      expect(Authentication::PasswordVerification.authenticate(user: other_user, password: "wrong")).to be_nil
    end

    expect(user.reload.failed_attempts).to eq(2)
    expect(user.access_locked?).to be(true)
    expect(other_user.reload.failed_attempts).to eq(2)
    expect(other_user.access_locked?).to be(false)
    expect(Authentication::PasswordVerification.authenticate(user: user, password: "Password123!")).to be_nil
    expect(Authentication::PasswordVerification.authenticate(user: other_user, password: "Password123!")).to eq(other_user)
    expect(other_user.reload.failed_attempts).to eq(0)
    expect(Authentication::User.maximum_attempts).to eq(class_limit)
    expect(Devise.maximum_attempts).to eq(global_limit)
  end

  it "uses the same tenant threshold for Devise's last-attempt warning" do
    allow(Devise).to receive(:paranoid).and_return(false)
    allow(Authentication::User).to receive(:last_attempt_warning).and_return(true)
    user.update_columns(failed_attempts: 1)

    expect(user.unauthenticated_message).to eq(:last_attempt)
    user.update_columns(failed_attempts: 2)
    expect(user.unauthenticated_message).to eq(:locked)
  end

  it "retains Devise's time-unlock and reset behavior after a tenant-limited lockout" do
    2.times { Authentication::PasswordVerification.authenticate(user: user, password: "wrong") }
    expect(user.reload.access_locked?).to be(true)

    travel_to((Authentication::User.unlock_in + 1.second).from_now) do
      expect(Authentication::PasswordVerification.authenticate(user: user, password: "Password123!")).to eq(user)
      expect(user.reload.locked_at).to be_nil
      expect(user.failed_attempts).to eq(0)
    end
  end
end
