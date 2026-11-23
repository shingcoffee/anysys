# frozen_string_literal: true

require "rails_helper"

# Captures the pre-cutover authorization behavior for a representative sample
# of admin routes. After Phase 5B cutover, this same spec must continue to pass.
# Failures = a route's protection regressed.
RSpec.describe "Legacy authorization baseline", type: :request do
  let(:customer) { create(:customer) }

  let(:member_user) { create(:user, customer: customer, role: :member) }
  let(:admin_user)  { create(:user, customer: customer, role: :admin) }
  let(:owner_user)  { create(:user, customer: customer, role: :admin) }

  REPRESENTATIVE_ROUTES = [
    { path: "/admin/maintenance",                    method: :get },
    { path: "/admin/maintenance/flowcharts",         method: :get },
    { path: "/admin/maintenance/entities",           method: :get }
  ].freeze

  shared_examples "an admin-protected route" do |route|
    context "#{route[:method].upcase} #{route[:path]}" do
      it "member: not allowed (302 redirect away)" do
        sign_in member_user
        public_send(route[:method], "/#{customer.id}#{route[:path]}")
        expect([302, 403]).to include(response.status)
      end

      it "owner: allowed (200 success or normal redirect)" do
        sign_in owner_user
        public_send(route[:method], "/#{customer.id}#{route[:path]}")
        # Owner should never be denied; expect success OR a non-deny redirect
        expect([200, 302, 304]).to include(response.status)
        # If 302, it should NOT be redirecting to root_path with an "Access denied" alert
        if response.status == 302
          expect(flash[:alert]).not_to match(/Access denied/i) if flash.is_a?(ActionDispatch::Flash::FlashHash)
        end
      end
    end
  end

  REPRESENTATIVE_ROUTES.each do |route|
    include_examples "an admin-protected route", route
  end
end
