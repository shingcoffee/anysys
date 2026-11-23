# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/authentication/roles", type: :request do
  include_context "as admin"

  let(:owner_role) { customer.roles.find_by(key: "owner") }
  let(:guard_path) { "/#{customer.id}/admin/settings/modules/authentication/roles" }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :post

  describe "GET new — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/settings/modules/authentication/roles/new" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET show — auth guards" do
    let(:role) { create(:role, customer: customer, key: "manager", name: "Manager") }
    let(:guard_path) { "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:role) { create(:role, customer: customer, key: "manager", name: "Manager") }
    let(:guard_path) { "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}/edit" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "PATCH update — auth guards" do
    let(:role) { create(:role, customer: customer, key: "manager", name: "Manager") }
    let(:guard_path) { "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}" }

    it_behaves_like "an admin-guarded request", :patch
  end

  describe "DELETE destroy — auth guards" do
    let(:role) { create(:role, customer: customer, key: "manager", name: "Manager") }
    let(:guard_path) { "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}" }

    it_behaves_like "an admin-guarded request", :delete
  end

  describe "GET /:cid/admin/settings/modules/authentication/roles" do
    it "lists all roles for the customer" do
      create(:role, customer: customer, name: "Manager", key: "manager")
      get "/#{customer.id}/admin/settings/modules/authentication/roles"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(
        I18n.t("settings_people.owner_name"), I18n.t("settings_people.admin_name"),
        I18n.t("settings_people.member_name"), "Manager"
      )
    end
  end

  describe "POST /:cid/admin/settings/modules/authentication/roles" do
    it "creates a custom role" do
      post "/#{customer.id}/admin/settings/modules/authentication/roles",
           params: { role: { key: "manager", name: "Manager", description: "x" } }
      expect(response).to redirect_to(/admin\/settings\/modules\/authentication\/roles/)
      expect(customer.roles.find_by(key: "manager")).not_to be_nil
    end

    it "rejects creating with reserved key" do
      post "/#{customer.id}/admin/settings/modules/authentication/roles",
           params: { role: { key: "owner", name: "Pwn" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(customer.roles.where(key: "owner").count).to eq(1)
    end
  end

  describe "PATCH /:cid/admin/settings/modules/authentication/roles/:id" do
    it "updates a custom role" do
      role = create(:role, customer: customer, key: "manager", name: "Manager")
      patch "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}",
            params: { role: { name: "Senior Manager" } }
      expect(role.reload.name).to eq("Senior Manager")
    end

    it "rejects updating a system role" do
      role = customer.roles.find_by(key: "admin")
      patch "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}",
            params: { role: { name: "Hacked" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /:cid/admin/settings/modules/authentication/roles/:id" do
    it "destroys a custom role" do
      role = create(:role, customer: customer, key: "manager")
      delete "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}"
      expect(Role.exists?(role.id)).to be false
    end

    it "rejects destroying a system role" do
      role = customer.roles.find_by(key: "owner")
      delete "/#{customer.id}/admin/settings/modules/authentication/roles/#{role.id}"
      expect(Role.exists?(role.id)).to be true
    end
  end
end
