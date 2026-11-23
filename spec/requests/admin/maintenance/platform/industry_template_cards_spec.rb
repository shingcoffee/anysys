# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::IndustryTemplateCards", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@itc.test", password: "password123") }
  let(:member_user)    { create(:user, :member, customer: other_customer, email: "member@itc.test", password: "password123") }

  let(:valid_industry) { "technology" }

  def cards_path(industry = valid_industry)
    admin_maintenance_platform_industry_template_template_cards_path(
      platform_customer.id, industry_template_id: industry
    )
  end

  let(:guard_path) { cards_path }

  it_behaves_like "a platform-owner-guarded GET"

  context "as non-owner admin" do
    before { sign_in admin_user }

    it "is denied" do
      get admin_maintenance_platform_industry_template_template_cards_path(
            other_customer.id, industry_template_id: valid_industry
          )
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as member" do
    before { sign_in member_user }

    it "is denied" do
      get admin_maintenance_platform_industry_template_template_cards_path(
            other_customer.id, industry_template_id: valid_industry
          )
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Happy path + branches (platform owner)
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    it "returns 200 with layout: false for a valid industry" do
      get cards_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects with alert for an invalid industry" do
      get cards_path("not_a_real_industry_xyz")
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/Invalid industry/i)
    end
  end
end
