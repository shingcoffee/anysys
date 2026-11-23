# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::IndustryTemplateNewTemplateSeeds", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@itnts.test", password: "password123") }
  let(:member_user)    { create(:user, :member, customer: other_customer, email: "member@itnts.test", password: "password123") }

  def new_template_seed_path
    admin_maintenance_platform_new_template_seed_path(platform_customer.id)
  end

  let(:guard_path) { new_template_seed_path }

  it_behaves_like "a platform-owner-guarded request", :post

  context "as non-owner admin" do
    before { sign_in admin_user }

    it "is denied" do
      post admin_maintenance_platform_new_template_seed_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as member" do
    before { sign_in member_user }

    it "is denied" do
      post admin_maintenance_platform_new_template_seed_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Happy path (platform owner)
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    it "creates new template mappings and redirects with notice" do
      post new_template_seed_path
      expect(response).to redirect_to(admin_maintenance_platform_industry_templates_path(platform_customer.id))
      expect(flash[:notice]).to match(/template mapping/i)
    end
  end
end
