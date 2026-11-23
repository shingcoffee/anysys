# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::IndustryTemplateDefaultSeeds", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@itds.test", password: "password123") }
  let(:member_user)    { create(:user, :member, customer: other_customer, email: "member@itds.test", password: "password123") }

  def default_seed_path
    admin_maintenance_platform_default_seed_path(platform_customer.id)
  end

  let(:guard_path) { default_seed_path }

  it_behaves_like "a platform-owner-guarded request", :post
  it_behaves_like "a platform-owner-guarded request", :delete

  context "as non-owner admin" do
    before { sign_in admin_user }

    it "is denied on create" do
      post admin_maintenance_platform_default_seed_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "is denied on destroy (reset)" do
      delete admin_maintenance_platform_default_seed_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as member" do
    before { sign_in member_user }

    it "is denied on create" do
      post admin_maintenance_platform_default_seed_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Happy path (platform owner)
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    it "POST create seeds default mappings and redirects with notice" do
      post default_seed_path
      expect(response).to redirect_to(admin_maintenance_platform_industry_templates_path(platform_customer.id))
      expect(flash[:notice]).to match(/Default mappings seeded/i)
    end

    it "DELETE destroy resets all mappings and redirects with notice" do
      delete default_seed_path
      expect(response).to redirect_to(admin_maintenance_platform_industry_templates_path(platform_customer.id))
      expect(flash[:notice]).to match(/reset to defaults/i)
    end
  end
end
