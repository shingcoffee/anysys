# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::EntityRestorations", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  # Create a soft-deleted entity via soft_delete so it appears in only_deleted.
  let!(:deleted_entity) do
    e = create(:entity, customer: customer)
    e.soft_delete
    e
  end

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "PATCH update — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/entities/#{deleted_entity.id}/restoration" }

    it_behaves_like "an admin-guarded request", :patch
  end

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  describe "PATCH update — admin restores a soft-deleted entity" do
    before { sign_in admin }

    it "restores the entity and redirects to the entities index" do
      patch "/#{customer.id}/admin/maintenance/entities/#{deleted_entity.id}/restoration"

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(admin_maintenance_entities_url(customer.id))

      restored = Entity.unscoped.find(deleted_entity.id)
      expect(restored.status).to eq("active")
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "PATCH update — cross-tenant access is forbidden" do
    let(:other_customer)    { create(:customer) }
    let!(:other_deleted) do
      e = create(:entity, customer: other_customer)
      e.soft_delete
      e
    end

    before { sign_in admin }

    it "returns 404 for another tenant's deleted entity" do
      patch "/#{customer.id}/admin/maintenance/entities/#{other_deleted.id}/restoration"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH update — forms left offline" do
    it "names the entity's offline forms" do
      sign_in admin
      entity = create(:entity, customer: customer, name: "Timesheet")
      create(:page, customer: customer, entity: entity, name: "Weekly hours", launched: true)
      entity.soft_delete

      patch "/#{customer.id}/admin/maintenance/entities/#{entity.id}/restoration"

      expect(flash[:notice]).to eq(
        "#{I18n.t('maint_core.flash.entity_restorations.restored', name: 'Timesheet')} " \
        "#{I18n.t('maint_core.flash.entity_restorations.offline_forms', names: 'Weekly hours')}"
      )
    end
  end
end
