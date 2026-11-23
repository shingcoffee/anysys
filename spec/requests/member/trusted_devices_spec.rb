# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member::TrustedDevices", type: :request do
  include_context "as member"

  def device_for(user)
    Authentication::TrustedDevice.create!(
      customer_id: user.customer_id, user_id: user.id,
      token_digest: SecureRandom.hex(16), expires_at: 30.days.from_now
    )
  end

  it "lets a member revoke their own device" do
    device = device_for(member)
    expect {
      delete "/#{member.customer_id}/member/trusted_devices/#{device.id}"
    }.to change { Authentication::TrustedDevice.exists?(device.id) }.from(true).to(false)
    expect(response).to have_http_status(:redirect)
  end

  it "404s (does not revoke) another user's device" do
    other_user = create(:user, :member, customer: customer)
    foreign_device = device_for(other_user)

    delete "/#{member.customer_id}/member/trusted_devices/#{foreign_device.id}"
    expect(response).to have_http_status(:not_found)
    expect(Authentication::TrustedDevice.exists?(foreign_device.id)).to be(true)
  end
end
