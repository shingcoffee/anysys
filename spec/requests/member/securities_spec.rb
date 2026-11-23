# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member::Securities", type: :request do
  include_context "as member"

  # ---------------------------------------------------------------------------
  # GET /:customer_id/member/security
  # ---------------------------------------------------------------------------
  describe "GET show" do
    it "returns 200 for the signed-in member" do
      get member_security_path(customer.id)
      expect(response).to have_http_status(:ok)
    end

    it "renders the security center page" do
      get member_security_path(customer.id)
      expect(response.body).to include("Security")
    end

    it "localizes trusted-device last used instead of ISO strftime" do
      device = Authentication::TrustedDevice.create!(
        customer_id: member.customer_id, user_id: member.id,
        token_digest: SecureRandom.hex(16), expires_at: 30.days.from_now,
        last_used_at: Time.zone.local(2026, 6, 15, 10, 30)
      )
      get member_security_path(customer.id)
      expect(response.body).to include(I18n.l(device.last_used_at, format: :long))
      expect(response.body).not_to include(device.last_used_at.strftime("%Y-%m-%d %H:%M"))
    end
  end

  # ---------------------------------------------------------------------------
  # Authorization
  # ---------------------------------------------------------------------------
  describe "authorization" do
    it "rejects an anonymous request" do
      sign_out member
      get member_security_path(customer.id)
      expect([302, 401]).to include(response.status)
    end

    it "rejects an admin-role user (member routes are member-only)" do
      sign_out member
      sign_in create(:user, :admin, customer: customer)
      get member_security_path(customer.id)
      # Member::SecuritiesController does not call allow_admin_member_preview!
      # so admins must not gain access.
      expect([302, 403]).to include(response.status)
      expect(response.status).not_to eq(200)
    end

    it "rejects the platform owner (owner is not a member role)" do
      sign_out member
      sign_in find_or_create_platform_owner
      get member_security_path(customer.id)
      expect([302, 403]).to include(response.status)
      expect(response.status).not_to eq(200)
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-user isolation — member A cannot access member B's security page
  # (both are under the same customer; the controller binds to current_user)
  # ---------------------------------------------------------------------------
  describe "cross-user isolation" do
    let(:other_member) { create(:user, :member, customer: customer) }

    it "does not expose another member's security page under a different customer scope" do
      other_customer = create(:customer)
      # The member belongs to `customer`; requesting under other_customer's cid
      # is either a 404 (record not found) or a redirect to their own tenant.
      sign_out member
      sign_in create(:user, :member, customer: other_customer)
      get member_security_path(customer.id)
      expect([302, 403, 404]).to include(response.status)
      expect(response.status).not_to eq(200)
    end
  end
end
