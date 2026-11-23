# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Core entity controller audit", type: :request do
  include_context "as admin"
  let!(:entity) { create(:entity, :with_name_status_schema, customer: customer) }
  let(:platform_owner) { find_or_create_platform_owner }

  describe "definition request shapes" do
    {
      property_schema: ["[null]", "1", "not-json", '[{"name":"Missing slug"}]',
                        '[{"name_slug":"field","config":1}]', '[{"name_slug":"field","validators":1}]',
                        '[{"name_slug":"field","config":{"options":[1]}}]'],
      associations: ["[null]", "{}"],
      attribute_groups: ["[null]", "1"],
      default_properties: ["[]"],
      referenced_template: ["[]", "null", '{"key":[]}']
    }.each do |key, invalid_values|
      invalid_values.each do |value|
        it "rejects #{key}=#{value.inspect} without creating a record or version" do
          sign_in platform_owner
          domain = create(:entity_domain, customer: customer)
          before_counts = [Entity.count, EntityVersion.count]

          post "/#{customer.id}/admin/maintenance/entities.json",
               params: { entity_domain_id: domain.id, entity: { name: "Invalid shape", key => value } }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body.fetch("errors")).to include(I18n.t("routes_audit.invalid_definition"))
          expect([Entity.count, EntityVersion.count]).to eq(before_counts)
        end
      end
    end

    it "preserves the existing definition on malformed update" do
      head_id = entity.current_version_id
      patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}.json",
            params: { entity: { property_schema: "[null]" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(entity.reload.current_version_id).to eq(head_id)
    end

    it "returns a controlled preview response for non-object template JSON" do
      # Simulate a stored pre-audit reference without invoking any builder renderer.
      allow_any_instance_of(Entity).to receive(:referenced_template).and_return("[]")
      expect(TemplatePreviewBuilder).not_to receive(:call)

      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/template_preview"

      expect(response).to redirect_to(admin_maintenance_entity_path(customer.id, entity))
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.entity_template_previews.invalid_template"))
    end

    it "rejects malformed stored preview rows before calling the builder renderer" do
      allow_any_instance_of(Entity).to receive(:referenced_template).and_return({ key: "blank", preview_rows: 1 }.to_json)
      expect(TemplatePreviewBuilder).not_to receive(:call)

      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/template_preview"

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.entity_template_previews.invalid_template"))
    end
  end

  describe "historical editing and lineage" do
    it "hydrates the chosen version and carries its ID in the existing form action" do
      old = entity.current_version
      old_schema = entity.property_schema_json
      entity.update!(description: "Current description", property_schema: [{ "name" => "New field", "name_slug" => "new_field", "html_type" => "text" }].to_json)
      head_id = entity.current_version_id

      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/versions/#{old.id}/edit"
      follow_redirect!

      expect(response).to have_http_status(:ok)
      form = Nokogiri::HTML(response.body).at_css("form[data-controller='entity-form']")
      expect(JSON.parse(form.at_css("input[name='entity[property_schema]']")["value"])).to eq(old_schema)
      expect(Addressable::URI.parse(form["action"]).query_values).to include("based_on_version_id" => old.id.to_s)
      expect(entity.reload.current_version_id).to eq(head_id)

      patch form["action"], params: { entity: { property_schema: old_schema.to_json, description: "Historical edit" } }

      expect(response).to have_http_status(:redirect)
      expect(entity.reload.current_version.based_on_version_id).to eq(old.id)
      expect(entity.description).to eq("Historical edit")
    end

    it "rejects a version from another entity when opening or saving historical edits" do
      foreign = create(:entity, customer: customer).current_version
      head_id = entity.current_version_id
      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}"
      expect(response).to have_http_status(:ok)

      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/edit", params: { version: foreign.id }
      expect(response).to have_http_status(:not_found)

      patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}.json",
            params: { based_on_version_id: foreign.id, entity: { description: "Forged lineage" } }
      expect(response).to have_http_status(:not_found)
      expect(entity.reload.current_version_id).to eq(head_id)
    end

    it "rejects malformed historical JSON instead of opening a blank editable definition" do
      version = entity.current_version
      allow_any_instance_of(EntityVersion).to receive(:payload).and_return("[]")

      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/edit", params: { version: version.id }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("routes_audit.invalid_definition"))
      expect(entity.reload.current_version_id).to eq(version.id)
    end

    it "never opens another tenant's override version of a shared entity" do
      shared = create(:entity, :shared)
      foreign_customer = create(:customer)
      Current.set(customer: foreign_customer, shared_resources_mode: false) do
        shared.description = "Foreign override"
        shared.save!
      end
      foreign_version = shared.entity_versions.find_by!(customer_id: foreign_customer.id)

      get "/#{customer.id}/admin/maintenance/entities/#{shared.id}/edit", params: { version: foreign_version.id }

      expect(response).to have_http_status(:not_found)
    end
  end

  it "copies display configuration without copying bridge identity" do
    sign_in platform_owner
    target = create(:entity, :with_name_status_schema, customer: customer)
    entity.update!(associations: [{
      "target_entity_id" => target.id,
      "target_entity_name" => target.name,
      "display_field" => "name", "display_field_label" => "Name",
      "additional_attributes" => []
    }].to_json)
    entity.sync_bridge_entities!

    get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/copy"

    expect(response).to have_http_status(:ok)
    associations = JSON.parse(Nokogiri::HTML(response.body).at_css("input[name='entity[associations]']")["value"])
    expect(associations.first).to include("display_field" => "name", "display_field_label" => "Name")
    expect(associations.first).not_to have_key("bridge_entity_id")
  end

  it "reports actual restoration failure instead of a success notice" do
    target = create(:entity, customer: customer,
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    entity.update!(associations: [{ "target_entity_id" => target.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)
    entity.sync_bridge_entities!
    bridge_id = entity.reload.associations_list.first["bridge_entity_id"]
    Entity.find(bridge_id).destroy!
    entity.update_columns(status: :inactive)

    patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}/restoration"

    expect(response).to have_http_status(:redirect)
    expect(flash[:notice]).to be_nil
    expect(flash[:alert]).to be_present
    expect(Entity.with_deleted.find(entity.id)).to be_inactive
  end
end
