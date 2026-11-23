# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::EntityIndexSettings", type: :request do
  include_context "as admin"

  let!(:entity) { create(:entity, :with_name_status_schema, customer: customer) }
  let(:member) { create(:user, :member, customer: customer) }
  let(:path) { admin_entity_index_setting_path(customer.id, entity) }
  let(:guard_path) { path }
  let(:valid_params) do
    { entity_index_setting: { visible_column_keys: %w[name status] } }
  end

  describe "PATCH update" do
    it_behaves_like "an admin-guarded request", :patch
    it "saves column preferences and redirects with flash" do
      patch path, params: valid_params
      expect(response).to redirect_to(admin_entity_path(customer.id, entity))
      follow_redirect!
      expect(response.body).to include("Column preferences saved")

      setting = EntityIndexSetting.find_by!(customer_id: customer.id, entity_id: entity.id)
      expect(setting.visible_column_keys).to eq(%i[name status])
    end

    it "saves column preferences for a shared entity" do
      shared = create(:entity, :shared, :with_name_status_schema)
      patch admin_entity_index_setting_path(customer.id, shared), params: valid_params
      expect(response).to redirect_to(admin_entity_path(customer.id, shared))

      setting = EntityIndexSetting.find_by!(customer_id: customer.id, entity_id: shared.id)
      expect(setting.visible_column_keys).to eq(%i[name status])
    end

    it "allows an empty array and hides attribute columns on subsequent GET show" do
      patch path, params: { entity_index_setting: { visible_column_keys: [""] } }
      expect(response).to redirect_to(admin_entity_path(customer.id, entity))

      setting = EntityIndexSetting.find_by!(customer_id: customer.id, entity_id: entity.id)
      expect(setting.visible_column_keys).to eq([])

      get admin_entity_path(customer.id, entity)
      expect(response).to have_http_status(:ok)
      # Attribute labels from schema should not appear as table headers when overlay is []
      expect(response.body).not_to match(/<th[^>]*>\s*Name\s*<\/th>/i)
      expect(response.body).not_to match(/<th[^>]*>\s*Status\s*<\/th>/i)
    end

    it "rejects unknown slugs with alert flash" do
      patch path, params: {
        entity_index_setting: { visible_column_keys: %w[name not_a_field] }
      }
      expect(response).to redirect_to(admin_entity_path(customer.id, entity))
      follow_redirect!
      expect(response.body).to include(
        I18n.t("admin_misc.entities.index_setting.errors.invalid_keys")
      )
      expect(EntityIndexSetting.where(customer_id: customer.id, entity_id: entity.id)).to be_empty
    end

    it "does not persist column preferences for anonymous users" do
      sign_out admin
      patch path, params: valid_params
      expect(EntityIndexSetting.where(customer_id: customer.id, entity_id: entity.id)).to be_empty
    end

    it "does not persist column preferences for a member" do
      sign_in member
      patch path, params: valid_params
      expect(EntityIndexSetting.where(customer_id: customer.id, entity_id: entity.id)).to be_empty
    end

    it "blocks a cross-tenant admin from updating another customer's entity" do
      other_customer = create(:customer)
      other_admin = create(:user, :admin, customer: other_customer)
      sign_in other_admin

      patch admin_entity_index_setting_path(customer.id, entity), params: valid_params
      expect(response).to have_http_status(:not_found)
        .or have_http_status(:forbidden)
        .or have_http_status(:found)
      expect(EntityIndexSetting.where(customer_id: customer.id, entity_id: entity.id)).to be_empty
      expect(EntityIndexSetting.where(customer_id: other_customer.id, entity_id: entity.id)).to be_empty
    end
  end
end
