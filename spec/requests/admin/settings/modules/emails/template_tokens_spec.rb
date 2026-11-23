# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Settings::Modules::Emails::TemplateTokens", type: :request do
  include_context "as admin"
  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let(:entity) { create(:entity, :with_name_status_schema, customer: customer) }
  let(:guard_path) { admin_settings_modules_emails_template_tokens_path(customer.id) }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :post

  describe "GET new — auth guards" do
    let(:guard_path) { new_admin_settings_modules_emails_template_token_path(customer.id) }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:token) { create(:email_template_token, customer: customer, entity: entity) }
    let(:guard_path) { edit_admin_settings_modules_emails_template_token_path(customer.id, token) }

    it_behaves_like "an admin-guarded GET"
  end

  describe "PATCH update — auth guards" do
    let(:token) { create(:email_template_token, customer: customer, entity: entity) }
    let(:guard_path) { admin_settings_modules_emails_template_token_path(customer.id, token) }

    it_behaves_like "an admin-guarded request", :patch
  end

  describe "DELETE destroy — auth guards" do
    let(:token) { create(:email_template_token, customer: customer, entity: entity) }
    let(:guard_path) { admin_settings_modules_emails_template_token_path(customer.id, token) }

    it_behaves_like "an admin-guarded request", :delete
  end

  describe "GET index" do
    it "lists platform variables without exposing UUIDs" do
      platform = Emails::TemplateToken.create!(
        source_type: Emails::TemplateToken::SOURCE_PLATFORM,
        source_key: "first_name",
        label: "first_name"
      )

      get admin_settings_modules_emails_template_tokens_path(customer.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("common.labels.first_name"))
      expect(response.body).not_to include("first_name")
      expect(response.body).not_to include(platform.uuid)
    end
  end

  describe "GET new" do
    it "labels the required entity picker and prefills selected fields without offering existing fields" do
      create(:email_template_token, customer: customer, entity: entity, attribute_slug: "status")
      get new_admin_settings_modules_emails_template_token_path(customer.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/<(?:input|select)[^>]*name="emails_template_token\[entity_id\]"[^>]*\brequired\b|<(?:input|select)[^>]*\brequired\b[^>]*name="emails_template_token\[entity_id\]"/)
      expect(response.body).to include('value="name"', 'value="Name"', 'data-controller="email-template-token-bulk"')
      expect(response.body).to include('Choose an entity', 'An entity defines which fields you can add')
      expect(response.body).not_to include('Record type')
      expect(response.body).not_to include('value="status"')
    end
  end

  describe "POST create" do
    def fields(*entries)
      entries.each_with_index.to_h { |(slug, label, selected), index| [index.to_s, { attribute_slug: slug, label: label, selected: selected }] }
    end

    it "creates every selected field with the supplied display names in one request" do
      expect {
        post admin_settings_modules_emails_template_tokens_path(customer.id), params: {
          emails_template_token: {
            entity_id: entity.id,
            fields: fields(["name", "Supporter name", "1"], ["status", "Current status", "1"])
          }
        }
      }.to change { Emails::TemplateToken.custom_for(customer.id).count }.by(2)

      expect(Emails::TemplateToken.custom_for(customer.id).order(:attribute_slug).pluck(:attribute_slug, :label)).to eq([
        ["name", "Supporter name"], ["status", "Current status"]
      ])
      expect(response).to redirect_to(admin_settings_modules_emails_template_tokens_path(customer.id))
    end

    it "creates only checked fields" do
      post admin_settings_modules_emails_template_tokens_path(customer.id), params: {
        emails_template_token: { entity_id: entity.id, fields: fields(["name", "Name", "0"], ["status", "Status", "1"]) }
      }
      expect(Emails::TemplateToken.custom_for(customer.id).pluck(:attribute_slug)).to eq(["status"])
    end

    it "returns 404 when the Email module is disabled" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: email_module
      ).update!(status: :suspended)

      expect {
        post admin_settings_modules_emails_template_tokens_path(customer.id), params: {
          emails_template_token: {
            entity_id: entity.id,
            fields: fields(["name", "Name", "1"])
          }
        }
      }.not_to change { Emails::TemplateToken.custom_for(customer.id).count }
      expect(response).to have_http_status(:not_found)
    end

    it "re-renders new with 422 when no entity or fields are selected" do
      expect {
        post admin_settings_modules_emails_template_tokens_path(customer.id), params: {
          emails_template_token: { entity_id: "", fields: {} }
        }
      }.not_to change { Emails::TemplateToken.custom_for(customer.id).count }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects cross-tenant entity ids" do
      foreign = create(:entity, :with_name_status_schema, customer: create(:customer))
      post admin_settings_modules_emails_template_tokens_path(customer.id), params: {
        emails_template_token: {
          entity_id: foreign.id,
          fields: fields(["name", "Bad", "1"])
        }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Emails::TemplateToken.custom_for(customer.id)).to be_empty
    end

    it "accepts an active shared entity" do
      shared = create(:entity, :shared, :with_name_status_schema)
      post admin_settings_modules_emails_template_tokens_path(customer.id), params: {
        emails_template_token: { entity_id: shared.id, fields: fields(["name", "Shared name", "1"]) }
      }
      expect(response).to have_http_status(:redirect)
      expect(Emails::TemplateToken.custom_for(customer.id).pluck(:entity_id)).to eq([shared.id])
    end

    it "rejects invalid fields atomically and preserves selections and custom names on the form" do
      expect {
        post admin_settings_modules_emails_template_tokens_path(customer.id), params: {
          emails_template_token: { entity_id: entity.id, fields: fields(["name", "Custom name", "1"], ["status", "", "1"]) }
        }
      }.not_to change { Emails::TemplateToken.custom_for(customer.id).count }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('value="Custom name"')
      expect(response.body).to include('selected="selected" value="' + entity.id.to_s + '"')
    end

    it "rejects an unknown schema attribute, duplicate selection, or an already-added field without saving anything" do
      create(:email_template_token, customer: customer, entity: entity, attribute_slug: "status")
      [fields(["name", "Name", "1"], ["bogus", "Bogus", "1"]),
       fields(["name", "Name", "1"], ["name", "Duplicate", "1"]),
       fields(["name", "Name", "1"], ["status", "Status", "1"])].each do |submitted|
        expect {
          post admin_settings_modules_emails_template_tokens_path(customer.id), params: {
            emails_template_token: { entity_id: entity.id, fields: submitted }
          }
        }.not_to change { Emails::TemplateToken.custom_for(customer.id).count }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it "rejects an empty selection" do
      post admin_settings_modules_emails_template_tokens_path(customer.id), params: {
        emails_template_token: { entity_id: entity.id, fields: fields(["name", "Name", "0"]) }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("settings_modules.email.bulk_errors.select_at_least_one"))
    end
  end

  describe "GET edit and PATCH update" do
    let!(:token) { create(:email_template_token, customer: customer, entity: entity, attribute_slug: "name", label: "Custom name") }

    it "keeps the saved display name and hides mappings owned by other tokens" do
      create(:email_template_token, customer: customer, entity: entity, attribute_slug: "status")
      get edit_admin_settings_modules_emails_template_token_path(customer.id, token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="Custom name"', 'Field mapping', 'An entity defines which fields you can add')
      expect(response.body).not_to include('<option value="status">')
    end

    it "updates the existing field without creating an additional token" do
      expect {
        patch admin_settings_modules_emails_template_token_path(customer.id, token), params: {
          emails_template_token: { entity_id: entity.id, attribute_slug: "status", label: "Updated status" }
        }
      }.not_to change { Emails::TemplateToken.custom_for(customer.id).count }
      expect(response).to redirect_to(admin_settings_modules_emails_template_tokens_path(customer.id))
      expect(token.reload.attributes.slice("attribute_slug", "label")).to eq({ "attribute_slug" => "status", "label" => "Updated status" })
    end

    it "keeps invalid submitted label and mapping values at 422 without saving the token" do
      submitted_label = "x" * 101
      patch admin_settings_modules_emails_template_token_path(customer.id, token), params: {
        emails_template_token: { entity_id: entity.id, attribute_slug: "status", label: submitted_label }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      page = Capybara.string(response.body)
      expect(page).to have_field("emails_template_token[label]", with: submitted_label)
      expect(page).to have_css('select[name="emails_template_token[attribute_slug]"] option[selected][value="status"]')
      expect(token.reload).to have_attributes(label: "Custom name", attribute_slug: "name", entity_id: entity.id)
    end

    it "preserves unknown submitted entity and slug as escaped form data without exposing another entity" do
      patch admin_settings_modules_emails_template_token_path(customer.id, token), params: {
        emails_template_token: { entity_id: "999999999", attribute_slug: "<unknown>", label: "" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      page = Capybara.string(response.body)
      expect(page).to have_field("emails_template_token[label]", with: "")
      expect(page).to have_css('select[name="emails_template_token[entity_id]"] option[selected][value="999999999"]')
      expect(page).to have_css('select[name="emails_template_token[attribute_slug]"] option[selected][value="<unknown>"]')
      attribute_map = JSON.parse(Nokogiri::HTML(response.body).at_css("[data-email-template-token-form-attributes-value]")["data-email-template-token-form-attributes-value"])
      expect(attribute_map.fetch("999999999")).to include(["<unknown>", "<unknown>"])
      expect(token.reload).to have_attributes(label: "Custom name", attribute_slug: "name", entity_id: entity.id)
    end

    it "rejects an already-added field rather than replacing another token" do
      create(:email_template_token, customer: customer, entity: entity, attribute_slug: "status")
      patch admin_settings_modules_emails_template_token_path(customer.id, token), params: {
        emails_template_token: { entity_id: entity.id, attribute_slug: "status", label: "Other name" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(token.reload.label).to eq("Custom name")
      expect(response.body).to include(I18n.t("settings_modules.email.edit_field_already_added"))
    end
  end

  describe "DELETE destroy" do
    it "destroys a custom variable" do
      token = create(:email_template_token, customer: customer, entity: entity)
      expect {
        delete admin_settings_modules_emails_template_token_path(customer.id, token)
      }.to change { Emails::TemplateToken.custom_for(customer.id).count }.by(-1)
    end

    it "does not destroy platform variables" do
      platform = Emails::TemplateToken.create!(
        source_type: Emails::TemplateToken::SOURCE_PLATFORM,
        source_key: "first_name",
        label: "first_name"
      )
      expect {
        delete admin_settings_modules_emails_template_token_path(customer.id, platform)
      }.not_to change(Emails::TemplateToken, :count)
      expect(response).to redirect_to(admin_settings_modules_emails_template_tokens_path(customer.id))
    end
  end
end
