# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::PageTemplateApplications", type: :request do
  let(:customer)     { create(:customer) }
  let(:admin)        { create(:user, :admin, customer: customer) }
  let(:page_entity)  { create(:entity, customer: customer) }

  # A page that has at least one field in its configuration so the "no fields"
  # guard is not triggered.
  let(:config_with_fields) do
    {
      "metadata" => { "entity_id" => page_entity.id },
      "pages"    => [
        {
          "id"     => "page_1",
          "fields" => [
            { "id" => "f1", "field_type" => "text", "label" => "Name", "property_slug" => "name" }
          ]
        }
      ]
    }.to_json
  end
  let!(:page_record) do
    # `configuration` is a virtual attribute backed by the head version's
    # content (Versionable) — assign + save so a version is committed,
    # not update_column (there is no longer a `configuration` DB column).
    create(:page, customer: customer).tap do |p|
      p.update!(configuration: config_with_fields)
    end
  end

  # A known template key that exists in PageLayoutTemplates.
  let(:valid_template_key) { "job_application" }

  def template_application_path(page = page_record) = "/#{customer.id}/admin/maintenance/pages/#{page.id}/template_application"

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "POST create — auth guards" do
    let(:guard_path) { template_application_path }

    it_behaves_like "an admin-guarded request", :post
  end

  # ---------------------------------------------------------------------------
  # POST create — happy path
  # ---------------------------------------------------------------------------

  describe "POST create — valid template key" do
    before { sign_in admin }

    it "returns 200 with a success flag and updated configuration" do
      post template_application_path,
           params: { template_key: valid_template_key }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["success"]).to be(true)
      expect(body).to have_key("configuration")
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — missing template_key
  # ---------------------------------------------------------------------------

  describe "POST create — blank template_key" do
    before { sign_in admin }

    it "returns 422 with an error message" do
      post template_application_path,
           params: { template_key: "" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to match(/required/i)
    end
  end

  describe "POST create — malformed configuration JSON" do
    before { sign_in admin }

    it "returns 422 instead of 500" do
      post template_application_path,
           params: { template_key: valid_template_key, configuration: "not-json" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Configuration is not valid JSON")
    end

    it "returns 422 when configuration JSON is not an object" do
      post template_application_path,
           params: { template_key: valid_template_key, configuration: "true" }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Configuration is not valid JSON")
    end

    it "accepts a nested JSON object instead of 500ing on JSON.parse" do
      post template_application_path,
           params: { template_key: valid_template_key, configuration: JSON.parse(config_with_fields) },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
    end

    it "returns 422 when a nested JSON configuration is not an object" do
      post template_application_path,
           params: { template_key: valid_template_key, configuration: [1, 2] }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Configuration is not valid JSON")
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — template not found
  # ---------------------------------------------------------------------------

  describe "POST create — unknown template_key" do
    before { sign_in admin }

    it "returns 404" do
      post template_application_path,
           params: { template_key: "totally_bogus_key_xyz" }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to match(/not found/i)
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — page has no fields
  # ---------------------------------------------------------------------------

  describe "POST create — page configuration has no fields" do
    let!(:empty_page) do
      create(:page, customer: customer).tap do |p|
        p.update!(configuration: {
          "metadata" => { "entity_id" => page_entity.id },
          "pages" => [{ "id" => "page_1", "fields" => [] }]
        }.to_json)
      end
    end

    before { sign_in admin }

    it "returns 422 with a 'no fields' error" do
      post template_application_path(empty_page),
           params: { template_key: valid_template_key }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to match(/no fields/i)
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "POST create — cross-tenant isolation" do
    let(:other_customer) { create(:customer) }
    let!(:other_page)    { create(:page, customer: other_customer) }

    before { sign_in admin }

    it "returns 404 for another tenant's page" do
      post template_application_path(other_page),
           params: { template_key: valid_template_key }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
