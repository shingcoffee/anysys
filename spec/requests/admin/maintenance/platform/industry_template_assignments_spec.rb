# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::IndustryTemplateAssignments", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@ita.test", password: "password123") }
  let(:member_user)    { create(:user, :member, customer: other_customer, email: "member@ita.test", password: "password123") }

  # Use a valid industry key from Customer::INDUSTRY_GROUPS
  let(:valid_industry) { "technology" }
  # Use a real template key from the registry
  let(:valid_template_key) { PageLayoutTemplates.keys.first }

  def assignments_path(industry = valid_industry)
    admin_maintenance_platform_industry_template_template_assignments_path(
      platform_customer.id, industry_template_id: industry
    )
  end

  def assignment_path(industry, key)
    admin_maintenance_platform_industry_template_template_assignment_path(
      platform_customer.id, industry_template_id: industry, id: key
    )
  end

  let(:guard_path) { assignments_path }

  it_behaves_like "a platform-owner-guarded request", :post

  describe "DELETE auth" do
    let(:guard_path) { assignment_path(valid_industry, valid_template_key) }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  context "as non-owner admin" do
    before { sign_in admin_user }

    it "is denied on create" do
      post admin_maintenance_platform_industry_template_template_assignments_path(
             other_customer.id, industry_template_id: valid_industry
           ), params: { template_key: valid_template_key }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "is denied on destroy" do
      delete admin_maintenance_platform_industry_template_template_assignment_path(
               other_customer.id, industry_template_id: valid_industry, id: valid_template_key
             )
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as member" do
    before { sign_in member_user }

    it "is denied on create" do
      post admin_maintenance_platform_industry_template_template_assignments_path(
             other_customer.id, industry_template_id: valid_industry
           ), params: { template_key: valid_template_key }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Happy path + branches (platform owner)
  # -------------------------------------------------------------------
  context "as platform owner" do
    before do
      sign_in platform_owner
      # Clean up any pre-existing mapping for this industry/template pair
      IndustryTemplateMapping.where(industry: valid_industry, template_key: valid_template_key).delete_all
    end

    describe "POST create" do
      it "adds a new template assignment and returns JSON" do
        post assignments_path, params: { template_key: valid_template_key }
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("added")
        expect(body["template_key"]).to eq(valid_template_key)
        expect(body["count"]).to be_a(Integer)
      end

      it "returns 422 when adding a duplicate assignment" do
        IndustryTemplateMapping.create!(industry: valid_industry, template_key: valid_template_key)
        post assignments_path, params: { template_key: valid_template_key }
        expect(response).to have_http_status(:unprocessable_entity)
        body = JSON.parse(response.body)
        expect(body).to have_key("errors")
      end

      it "returns 404 for an invalid industry" do
        post admin_maintenance_platform_industry_template_template_assignments_path(
               platform_customer.id, industry_template_id: "invalid_industry_xyz"
             ), params: { template_key: valid_template_key }
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "DELETE destroy" do
      before do
        IndustryTemplateMapping.find_or_create_by!(industry: valid_industry, template_key: valid_template_key)
      end

      it "removes the template assignment and returns JSON" do
        delete assignment_path(valid_industry, valid_template_key)
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("removed")
        expect(body["template_key"]).to eq(valid_template_key)
      end

      it "returns 404 when the mapping does not exist" do
        delete assignment_path(valid_industry, "nonexistent_template_key_xyz")
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 for an invalid industry" do
        delete admin_maintenance_platform_industry_template_template_assignment_path(
                 platform_customer.id, industry_template_id: "bogus_industry", id: valid_template_key
               )
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
