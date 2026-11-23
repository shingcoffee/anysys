# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::PageFieldOptions", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  let(:field_id)    { "field_abc" }
  let(:dyn_field_id) { "field_dyn" }

  let(:entity) { create(:entity, :with_name_status_schema, customer: customer) }

  # Page with a static field and a dynamic-options field backed by an entity query.
  let(:config_with_dynamic) do
    {
      "metadata" => { "entity_id" => entity.id },
      "pages"    => [
        {
          "id"     => "page_1",
          "fields" => [
            { "id" => field_id,    "field_type" => "text",   "label" => "Name" },
            {
              "id"         => dyn_field_id,
              "field_type" => "select",
              "label"      => "Status",
              "dynamic_options" => {
                "options_source" => "query",
                "entity_id"      => entity.id.to_s
              }
            }
          ]
        }
      ]
    }.to_json
  end

  let!(:page_record) do
    # `configuration` is a virtual attribute backed by the head version's
    # content (Versionable) — assign + save so a version is committed,
    # not update_column (there is no longer a `configuration` DB column).
    create(:page, customer: customer).tap { |p| p.update!(configuration: config_with_dynamic) }
  end

  def field_options_path(page = page_record, field = field_id)
    "/#{customer.id}/admin/maintenance/pages/#{page.id}/field_options/#{field}"
  end

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "GET show — auth guards" do
    let(:guard_path) { field_options_path }

    it_behaves_like "an admin-guarded GET"
  end

  # ---------------------------------------------------------------------------
  # Static field — no dynamic_options → empty array
  # ---------------------------------------------------------------------------

  describe "GET show — static field (no dynamic_options)" do
    before { sign_in admin }

    it "returns 200 with an empty array" do
      get field_options_path, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # Unknown field_id → 404
  # ---------------------------------------------------------------------------

  describe "GET show — unknown field_id" do
    before { sign_in admin }

    it "returns 404" do
      get field_options_path(page_record, "nonexistent_field"), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # Dynamic options — options_source == "query", entity exists
  # ---------------------------------------------------------------------------

  describe "GET show — dynamic options field, entity present" do
    before { sign_in admin }

    it "returns 200 with a JSON array (may be empty when no entries exist)" do
      get field_options_path(page_record, dyn_field_id), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_an(Array)
    end
  end

  # ---------------------------------------------------------------------------
  # Dynamic options — entity_id refers to a non-existent entity → empty array
  # ---------------------------------------------------------------------------

  describe "GET show — dynamic options field, entity missing" do
    before { sign_in admin }

    let(:config_missing_entity) do
      {
        "metadata" => { "entity_id" => entity.id },
        "pages"    => [
          {
            "id"     => "page_1",
            "fields" => [
              {
                "id"         => dyn_field_id,
                "field_type" => "select",
                "label"      => "Status",
                "dynamic_options" => {
                  "options_source" => "query",
                  "entity_id"      => "999999999"
                }
              }
            ]
          }
        ]
      }.to_json
    end

    let!(:page_no_entity) do
      create(:page, customer: customer).tap { |p| p.update!(configuration: config_missing_entity) }
    end

    it "returns 200 with an empty array" do
      get field_options_path(page_no_entity, dyn_field_id), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # Dynamic options — options_source is entity_entries → labelled list
  # ---------------------------------------------------------------------------

  describe "GET show — dynamic options with non-query source" do
    before { sign_in admin }

    let(:course) do
      create(:entity, customer: customer, name: "Course", property_schema: [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" }
      ].to_json)
    end

    let(:config_entity_entries) do
      {
        "metadata" => { "entity_id" => entity.id },
        "pages"    => [
          {
            "id"     => "page_1",
            "fields" => [
              {
                "id"         => dyn_field_id,
                "field_type" => "select",
                "label"      => "Course",
                "dynamic_options" => {
                  "options_source" => "entity_entries",
                  "entity_id"      => course.id.to_s,
                  "label_field"    => "title"
                }
              }
            ]
          }
        ]
      }.to_json
    end

    let!(:page_entity_entries) do
      create(:page, customer: customer).tap { |p| p.update!(configuration: config_entity_entries) }
    end

    let!(:biology) { create(:entity_entry, customer: customer, entity: course, data: { title: "Biology" }.to_json) }
    let!(:chemistry) { create(:entity_entry, customer: customer, entity: course, data: { title: "Chemistry" }.to_json) }

    it "returns the labelled list of entity entries" do
      get field_options_path(page_entity_entries, dyn_field_id), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([
        { "label" => "Biology", "value" => biology.id.to_s },
        { "label" => "Chemistry", "value" => chemistry.id.to_s }
      ])
    end
  end

  # ---------------------------------------------------------------------------
  # entity_entries nested inside a columns layout is still found
  # ---------------------------------------------------------------------------

  describe "GET show — entity_entries field nested in columns" do
    before { sign_in admin }

    let(:course) do
      create(:entity, customer: customer, name: "Course", property_schema: [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" }
      ].to_json)
    end

    let(:config_nested) do
      {
        "metadata" => { "entity_id" => entity.id },
        "pages"    => [
          {
            "id"     => "page_1",
            "fields" => [
              {
                "id"         => "cols",
                "field_type" => "columns",
                "property_type" => "layout",
                "columns"    => [
                  {
                    "fields" => [
                      {
                        "id"         => dyn_field_id,
                        "field_type" => "select",
                        "label"      => "Course",
                        "dynamic_options" => {
                          "options_source" => "entity_entries",
                          "entity_id"      => course.id.to_s,
                          "label_field"    => "title"
                        }
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }.to_json
    end

    let!(:page_nested) do
      create(:page, customer: customer).tap { |p| p.update!(configuration: config_nested) }
    end

    it "finds the nested field so the response is not 404" do
      get field_options_path(page_nested, dyn_field_id), as: :json

      expect(response).not_to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # query field whose label_field is id → empty list (id is not labelable)
  # ---------------------------------------------------------------------------

  describe "GET show — query field with label_field id" do
    before { sign_in admin }

    let(:config_id_label) do
      {
        "metadata" => { "entity_id" => entity.id },
        "pages"    => [
          {
            "id"     => "page_1",
            "fields" => [
              {
                "id"         => dyn_field_id,
                "field_type" => "select",
                "label"      => "Status",
                "dynamic_options" => {
                  "options_source" => "query",
                  "entity_id"      => entity.id.to_s,
                  "label_field"    => "id"
                }
              }
            ]
          }
        ]
      }.to_json
    end

    let!(:page_id_label) do
      create(:page, customer: customer).tap { |p| p.update!(configuration: config_id_label) }
    end

    it "returns an empty array" do
      get field_options_path(page_id_label, dyn_field_id), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # Dynamic options — with order_by and limit (exercises those branches)
  # ---------------------------------------------------------------------------

  describe "GET show — dynamic options with order_by and limit" do
    before { sign_in admin }

    let(:config_ordered) do
      {
        "metadata" => { "entity_id" => entity.id },
        "pages"    => [
          {
            "id"     => "page_1",
            "fields" => [
              {
                "id"         => dyn_field_id,
                "field_type" => "select",
                "label"      => "Status",
                "dynamic_options" => {
                  "options_source"  => "query",
                  "entity_id"       => entity.id.to_s,
                  "order_by"        => "name",
                  "order_direction" => "asc",
                  "limit"           => "5",
                  "label_field"     => "name",
                  "value_field"     => "status"
                }
              }
            ]
          }
        ]
      }.to_json
    end

    let!(:page_ordered) do
      create(:page, customer: customer).tap { |p| p.update!(configuration: config_ordered) }
    end

    it "returns 200 and applies order/limit without error" do
      get field_options_path(page_ordered, dyn_field_id), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to be_an(Array)
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "cross-tenant isolation" do
    let(:other_customer) { create(:customer) }
    let!(:other_page)    { create(:page, customer: other_customer) }

    before { sign_in admin }

    it "returns 404 for another tenant's page" do
      get field_options_path(other_page), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
