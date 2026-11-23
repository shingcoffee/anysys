# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::EntityTemplatePreviews", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  # An entity without a referenced_template
  let!(:entity_no_template) { create(:entity, customer: customer) }

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "GET show — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/#{entity_no_template.id}/template_preview" }

    it_behaves_like "an admin-guarded GET"
  end

  # ---------------------------------------------------------------------------
  # No referenced_template branch
  # ---------------------------------------------------------------------------

  describe "GET show — entity has no referenced_template" do
    before { sign_in admin }

    it "redirects back to the entity detail page with an alert" do
      get "/#{customer.id}/admin/maintenance/entities/#{entity_no_template.id}/template_preview"

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/no referenced template/i)
    end
  end

  # ---------------------------------------------------------------------------
  # Invalid JSON template branch
  # ---------------------------------------------------------------------------

  describe "GET show — entity has an invalid referenced_template JSON string" do
    let!(:entity_bad_json) do
      create(:entity, customer: customer, referenced_template: "not-json{{")
    end

    before { sign_in admin }

    it "redirects back to the entity detail page with an alert" do
      get "/#{customer.id}/admin/maintenance/entities/#{entity_bad_json.id}/template_preview"

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/invalid template data/i)
    end
  end

  # ---------------------------------------------------------------------------
  # Missing :key in parsed template data
  # ---------------------------------------------------------------------------

  describe "GET show — referenced_template JSON has no :key" do
    let!(:entity_no_key) do
      create(:entity, customer: customer,
             referenced_template: { name: "My Template" }.to_json)
    end

    before { sign_in admin }

    it "redirects back to the entity detail page with an alert" do
      get "/#{customer.id}/admin/maintenance/entities/#{entity_no_key.id}/template_preview"

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/invalid template data/i)
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "GET show — cross-tenant access is forbidden" do
    let(:other_customer) { create(:customer) }
    let!(:other_entity)  { create(:entity, customer: other_customer) }

    before { sign_in admin }

    it "returns 404 for another tenant's entity" do
      get "/#{customer.id}/admin/maintenance/entities/#{other_entity.id}/template_preview"
      expect(response).to have_http_status(:not_found)
    end
  end
end
