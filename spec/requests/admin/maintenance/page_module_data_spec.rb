# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::PageModuleData", type: :request do
  let(:customer)    { create(:customer) }
  let(:admin)       { create(:user, :admin, customer: customer) }
  let(:page_entity) { create(:entity, customer: customer) }

  # A page configuration that has a known module entry.
  let(:module_id) { "mod_1" }
  let(:config_with_module) do
    {
      "metadata" => { "entity_id" => page_entity.id },
      "pages"    => [{ "id" => "page_1", "fields" => [] }],
      "modules"  => [
        {
          "id"          => module_id,
          "entity_id"   => nil,
          "module_type" => "entity_list"
        }
      ]
    }.to_json
  end

  let!(:page_record) do
    # `configuration` is a virtual attribute backed by the head version's
    # content (Versionable) — assign + save so a version is committed,
    # not update_column (there is no longer a `configuration` DB column).
    create(:page, customer: customer).tap do |p|
      p.update!(configuration: config_with_module)
    end
  end

  def module_data_path(page = page_record, mod_id = module_id)
    "/#{customer.id}/admin/maintenance/pages/#{page.id}/module_data/#{mod_id}"
  end

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "GET show — auth guards" do
    let(:guard_path) { module_data_path }

    it_behaves_like "an admin-guarded GET"
  end

  # ---------------------------------------------------------------------------
  # GET show — module_id not found in page configuration
  # ---------------------------------------------------------------------------

  describe "GET show — unknown module_id" do
    before { sign_in admin }

    it "returns 404 with a descriptive error" do
      get module_data_path(page_record, "nonexistent_mod"), as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to match(/module not found/i)
    end
  end

  describe "GET show — non-list module" do
    before { sign_in admin }

    it "returns 422 instead of 500" do
      get module_data_path, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Module is not a list")
    end
  end

  describe "GET show — modules is not a list of objects" do
    before { sign_in admin }

    it "returns 422 when modules is a JSON object" do
      page_record.update!(configuration: {
        "metadata" => { "entity_id" => page_entity.id },
        "pages" => [{ "id" => "page_1", "fields" => [] }],
        "modules" => {}
      }.to_json)

      get module_data_path, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Page modules configuration is invalid")
    end

    it "returns 404 rather than 500 when a module slot is null" do
      page_record.update!(configuration: {
        "metadata" => { "entity_id" => page_entity.id },
        "pages" => [{ "id" => "page_1", "fields" => [] }],
        "modules" => [nil]
      }.to_json)

      get module_data_path, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # GET show — page belongs to another tenant
  # ---------------------------------------------------------------------------

  describe "GET show — cross-tenant isolation" do
    let(:other_customer) { create(:customer) }
    let!(:other_page)    { create(:page, customer: other_customer) }

    before { sign_in admin }

    it "returns 404 for another tenant's page" do
      get module_data_path(other_page), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
