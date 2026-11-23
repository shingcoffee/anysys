# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::EntityCopies", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:platform_owner) { find_or_create_platform_owner }
  let!(:entity)  { create(:entity, customer: customer) }

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "GET show — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/#{entity.id}/copy" }

    it_behaves_like "an admin-guarded GET"
  end

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  describe "GET show — a tenant admin" do
    before { sign_in admin }

    it "is refused, since copying is a manual create" do
      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/copy"
      expect(flash[:alert]).to eq(I18n.t("common.errors.authorization.platform_owner_required"))

      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/copy.json"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET show — the platform owner copies an entity" do
    before { sign_in platform_owner }

    it "starts the copy in the source's domain" do
      domain = create(:entity_domain, customer: customer)
      create(:entity_domain, customer: customer, name: "Other")
      EntityDomains::Memberships.place!(entity, domain)

      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/copy"

      select = Nokogiri::HTML(response.body).at_css("select#entity_domain_id")
      expect(select.at_css("option[selected]")["value"]).to eq(domain.id.to_s)
    end

    it "returns 200 and pre-populates the new-entity form with 'Copy of <name>'" do
      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/copy"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Copy of #{entity.name}")
    end

    it "copies display_label, extended_model, and attribute_groups onto the new form" do
      enable_module!("payment", customer).set_extendable_model!("Payments::Order", true)
      groups = [{ "id" => "g_1", "name" => "Contact", "icon" => "mail", "color" => "indigo" }]
      entity.update!(
        display_label: "Shown Label",
        extended_model: "Payments::Order",
        attribute_groups: groups
      )

      get "/#{customer.id}/admin/maintenance/entities/#{entity.id}/copy"

      copy = assigns(:entity)
      expect(copy.display_label).to eq("Shown Label")
      expect(copy.extended_model).to eq("Payments::Order")
      expect(copy.attribute_groups_json).to eq(groups)
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "GET show — shared entity is not copy-to-customer" do
    let!(:shared_entity) { create(:entity, :shared, name: "Global Entity") }

    before { sign_in platform_owner }

    it "returns 404" do
      get "/#{customer.id}/admin/maintenance/entities/#{shared_entity.id}/copy"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET show — cross-tenant access is forbidden" do
    let(:other_customer) { create(:customer) }
    let!(:other_entity)  { create(:entity, customer: other_customer) }

    before { sign_in platform_owner }

    it "returns 404 for another tenant's entity" do
      get "/#{customer.id}/admin/maintenance/entities/#{other_entity.id}/copy"
      expect(response).to have_http_status(:not_found)
    end
  end
end
