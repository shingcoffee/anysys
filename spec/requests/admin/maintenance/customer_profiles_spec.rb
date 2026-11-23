# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::CustomerProfiles", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/maintenance/customer_profile" }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :patch

  describe "GET edit — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/customer_profile/edit" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET show" do
    it "renders 200 with the organization's profile details" do
      get "/#{customer.id}/admin/maintenance/customer_profile"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(customer.name)
      expect(response.body).to include("Organization Identity")
      expect(response.body).to include("Contact Information")
      expect(response.body).to include("Account Status")
      expect(response.body).to include(edit_admin_maintenance_customer_profile_path(customer.id))
    end

    it "localizes industry instead of titleize" do
      get "/#{customer.id}/admin/maintenance/customer_profile"
      expect(response.body).to include(I18n.t("customers.industries.technology"))
    end

    it "localizes industry in zh-CN" do
      get "/#{customer.id}/admin/maintenance/customer_profile", params: { locale: "zh-CN" }
      expect(response.body).to include(I18n.t("customers.industries.technology", locale: :"zh-CN"))
    end
  end

  describe "GET edit" do
    it "renders 200 with the edit form pre-filled with current values" do
      get "/#{customer.id}/admin/maintenance/customer_profile/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Customer Profile")
      expect(response.body).to include('name="customer[name]"')
      expect(response.body).to include('name="customer[industry]"')
      expect(response.body).to include('name="customer[tier]"')
      expect(response.body).to include(%(value="#{customer.name}"))
    end
  end

  describe "PATCH update — valid params" do
    it "redirects to show with a success notice and persists changes" do
      patch "/#{customer.id}/admin/maintenance/customer_profile",
            params: { customer: { name: "Renamed Org", contact: "Jane Doe" } }

      expect(response).to have_http_status(:redirect)
      follow_redirect!

      expect(response.body).to include("Customer profile updated successfully.")
      customer.reload
      expect(customer.name).to eq("Renamed Org")
      expect(customer.contact).to eq("Jane Doe")
    end
  end

  describe "PATCH update — invalid params" do
    it "re-renders edit with 422 and leaves the record unchanged" do
      original_name = customer.name

      patch "/#{customer.id}/admin/maintenance/customer_profile",
            params: { customer: { name: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Edit Customer Profile")
      expect(response.body).to include(CGI.escapeHTML("can't be blank"))

      customer.reload
      expect(customer.name).to eq(original_name)
    end
  end

  describe "PATCH update — tier is billing-controlled" do
    it "ignores a tier param from a non-owner tenant admin (tier unchanged)" do
      expect(customer.tier).to eq("basic")

      patch "/#{customer.id}/admin/maintenance/customer_profile",
            params: { customer: { name: customer.name, tier: "enterprise" } }

      expect(response).to have_http_status(:redirect)
      customer.reload
      expect(customer.tier).to eq("basic")
    end
  end
end

RSpec.describe "Admin::Maintenance::CustomerProfiles — platform owner tier control", type: :request do
  include_context "as platform owner"

  describe "PATCH update — platform owner CAN set tier" do
    it "persists the tier change" do
      patch "/#{customer.id}/admin/maintenance/customer_profile",
            params: { customer: { name: customer.name, tier: "enterprise" } }

      expect(response).to have_http_status(:redirect)
      customer.reload
      expect(customer.tier).to eq("enterprise")
    end
  end
end
