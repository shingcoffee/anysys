# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member::Dashboards", type: :request do
  let(:customer)    { create(:customer) }
  let(:member_user) { create(:user, :member, customer: customer) }
  let(:dashboard_url) { "/#{customer.id}/member" }

  before { enable_module!("authentication", customer, name: "Authentication") }

  describe "GET /:customer_id/member" do
    # Anonymous / admin role-gate coverage lives in member/base_authorization_spec.rb.
    context "when signed in as a member" do
      before { sign_in member_user }

      it "renders the time-based greeting and member shell" do
        travel_to Time.zone.local(2026, 7, 7, 9, 0, 0) do
          get dashboard_url
        end

        expect(response.body).to include("Good morning")
        expect(response.body).to include("data-shell=\"member\"")
      end

      it "renders the member's display information" do
        get dashboard_url
        expect(response.body).to include(member_user.email)
      end

      it "points Sign out at Devise /auth/sign_out, not a tenant-prefixed 404" do
        get dashboard_url
        expect(response.body).to include('href="/auth/sign_out"')
        expect(response.body).not_to include("/#{customer.id}/auth/sign_out")
      end
    end
  end
end
