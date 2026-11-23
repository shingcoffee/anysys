# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::User, "trusted device revocation" do
  let(:customer) do
    Customer.find_or_create_by!(id: 81721200) { |c| c.name = "Plat"; c.industry = :technology; c.tier = :basic }
  end
  let(:user) do
    u = described_class.create!(customer_id: customer.id, email: "a@x.com",
      password: "Password!234", first_name: "A", last_name: "B", confirmed_at: Time.current)
    u.generate_otp_secret!
    u.enable_mfa!
    u
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

  it "wipes trusted devices when otp_secret rotates to a new (non-nil) value" do
    trust!
    user.generate_otp_secret!
    expect(user.trusted_devices.count).to eq(0)
  end
end
