# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::FieldTemplates", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  let(:valid_params) do
    {
      field_template: {
        name: "My Template",
        category: "text",
        description: "A test template",
        configuration: { field_type: "text", label: "Name" }
      }
    }
  end

  # Persist a FieldTemplate with the common `{ field_type: "text" }` configuration.
  # Extra attributes (e.g. category:) pass through as keyword overrides.
  def create_field_template(name:, customer_id: customer.id, built_in: false, **overrides)
    FieldTemplate.create!(
      customer_id: customer_id,
      name: name,
      configuration: { field_type: "text" },
      built_in: built_in,
      **overrides
    )
  end

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "GET index — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/field_templates" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "POST create — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/field_templates" }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "PATCH update — auth guards" do
    let!(:template) { create_field_template(name: "Guard Template") }
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/field_templates/#{template.id}" }

    it_behaves_like "an admin-guarded request", :patch
  end

  describe "DELETE destroy — auth guards" do
    let!(:template) { create_field_template(name: "Guard Template") }
    let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/field_templates/#{template.id}" }

    it_behaves_like "an admin-guarded request", :delete
  end

  # ---------------------------------------------------------------------------
  # GET index — happy path
  # ---------------------------------------------------------------------------

  describe "GET index" do
    let!(:own_template) do
      create_field_template(name: "Text Template", category: "text")
    end
    let(:other_customer) { create(:customer) }
    let!(:other_template) do
      create_field_template(name: "Other Template", customer_id: other_customer.id, category: "text")
    end

    before { sign_in admin }

    it "returns 200 with only the current tenant's templates" do
      get "/#{customer.id}/admin/maintenance/pages/field_templates", as: :json

      expect(response).to have_http_status(:ok)
      names = response.parsed_body.map { |t| t["name"] }
      expect(names).to include("Text Template")
      expect(names).not_to include("Other Template")
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — happy path
  # ---------------------------------------------------------------------------

  describe "POST create" do
    before { sign_in admin }

    it "creates a field template scoped to the current customer" do
      expect {
        post "/#{customer.id}/admin/maintenance/pages/field_templates",
             params: valid_params, as: :json
      }.to change(FieldTemplate, :count).by(1)

      expect(response).to have_http_status(:created)
      created = FieldTemplate.order(:created_at).last
      expect(created.customer_id).to eq(customer.id)
      expect(created.name).to eq("My Template")
    end

    it "returns 422 when name is blank" do
      post "/#{customer.id}/admin/maintenance/pages/field_templates",
           params: { field_template: { name: "", configuration: { field_type: "text" } } },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH update — happy path
  # ---------------------------------------------------------------------------

  describe "PATCH update" do
    let!(:template) { create_field_template(name: "Old Name") }

    before { sign_in admin }

    it "updates the template and returns 200" do
      patch "/#{customer.id}/admin/maintenance/pages/field_templates/#{template.id}",
            params: { field_template: { name: "New Name", configuration: { field_type: "text" } } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(template.reload.name).to eq("New Name")
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy — happy path
  # ---------------------------------------------------------------------------

  describe "DELETE destroy" do
    let!(:template) { create_field_template(name: "Deletable") }

    before { sign_in admin }

    it "deletes the template and returns 204" do
      expect {
        delete "/#{customer.id}/admin/maintenance/pages/field_templates/#{template.id}",
               as: :json
      }.to change(FieldTemplate, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    context "when template is built_in" do
      let!(:builtin_template) { create_field_template(name: "Built-in", built_in: true) }

      it "returns 422 and does not delete the record" do
        expect {
          delete "/#{customer.id}/admin/maintenance/pages/field_templates/#{builtin_template.id}",
                 as: :json
        }.not_to change(FieldTemplate, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
