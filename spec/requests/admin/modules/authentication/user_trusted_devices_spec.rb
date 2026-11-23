# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Authentication::UserTrustedDevices", type: :request do
  include_context "as admin"

  let(:target_user) { create(:user, :member, customer: customer) }
  let(:device) { device_for(target_user) }
  let(:guard_path) { "/#{customer.id}/admin/modules/authentication/users/#{target_user.id}/trusted_devices/#{device.id}" }

  it_behaves_like "an admin-guarded request", :delete

  def device_for(user)
    Authentication::TrustedDevice.create!(
      customer_id: user.customer_id, user_id: user.id,
      token_digest: SecureRandom.hex(16), expires_at: 30.days.from_now
    )
  end

  it "revokes a device belonging to a same-tenant user" do
    device = device_for(target_user)
    expect {
      delete "/#{customer.id}/admin/modules/authentication/users/#{target_user.id}/trusted_devices/#{device.id}"
    }.to change { Authentication::TrustedDevice.exists?(device.id) }.from(true).to(false)
    expect(response).to have_http_status(:redirect)
  end

  it "404s when the device belongs to a user in another tenant" do
    other = create(:customer)
    other_user = create(:user, :member, customer: other)
    foreign_device = device_for(other_user)

    delete "/#{customer.id}/admin/modules/authentication/users/#{other_user.id}/trusted_devices/#{foreign_device.id}"
    expect(response).to have_http_status(:not_found)
    expect(Authentication::TrustedDevice.exists?(foreign_device.id)).to be(true)
  end

  it "404s when the device belongs to a different user than the path user" do
    another_user = create(:user, :member, customer: customer)
    device = device_for(another_user)

    delete "/#{customer.id}/admin/modules/authentication/users/#{target_user.id}/trusted_devices/#{device.id}"
    expect(response).to have_http_status(:not_found)
    expect(Authentication::TrustedDevice.exists?(device.id)).to be(true)
  end
end
