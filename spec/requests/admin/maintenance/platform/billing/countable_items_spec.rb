# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/maintenance/platform/billing/countable_items", type: :request do
  let!(:platform_owner) { find_or_create_platform_owner }
  let(:platform_cid) { platform_owner.customer_id }
  let!(:item) { Billing::CountableItem.create!(key: "page", label: "Pages", enabled: false, position: 0, period: "total") }
  let(:guard_path) { admin_maintenance_platform_billing_countable_items_path(platform_cid) }

  it_behaves_like "a platform-owner-guarded GET"
  it_behaves_like "a platform-owner-guarded request", :patch

  describe "owner catalog requests" do
    before { sign_in platform_owner }

    it "enables and disables a non-core countable item" do
      storage = Billing::CountableItem.create!(key: "storage", label: "Storage", enabled: false, position: 4, period: "total")
      patch guard_path, params: { items: { "0" => {
        id: storage.id, label: "Storage", enabled: "true", position: 4, period: "total"
      } } }
      expect(response).to have_http_status(:see_other)
      expect(storage.reload.enabled).to be(true)

      patch guard_path, params: { items: { "0" => {
        id: storage.id, label: "Storage", enabled: "false", position: 4, period: "total"
      } } }
      expect(storage.reload.enabled).to be(false)
    end

    it "does not seed or sync the catalog during GET" do
      expect(Billing::Countable::CatalogSync).not_to receive(:call)
      expect { get guard_path }.not_to change(Billing::CountableItem, :count)
      expect(response).to have_http_status(:ok)
    end

    it "keeps the billing tab strip and the header save action" do
      get guard_path
      expect(response.body).to include("data-billing-nav")
      expect(response.body).to include('form="countable-items-form"')
    end

    it "normalizes indexed form input and sends only editable fields to the atomic catalog command" do
      expect(Billing::Catalog::UpdateCountableItems).to receive(:call).with(items: [
        { "id" => item.id.to_s, "label" => "Web Pages", "enabled" => "false", "position" => "3", "period" => "total" }
      ]).and_return(Billing::Result.new(status: :saved))
      patch guard_path, params: { items: { "0" => {
        id: item.id, label: "Web Pages", enabled: "false", position: 3, period: "total", key: "forged", customer_id: 1
      } } }
      expect(response).to have_http_status(:see_other)
      expect(item.reload.key).to eq("page")
    end

    it "retains a failed items form and does not partially write rows in the controller" do
      form = Billing::Catalog::UpdateCountableItems::Form.new(OpenStruct.new)
      form.validate(items: [{ id: item.id, enabled: "true", label: "Submitted", position: "broken", period: "total" }])
      allow(Billing::Catalog::UpdateCountableItems).to receive(:call).and_return(
        Billing::Result.new(status: :invalid, form: form, errors: form.errors.messages)
      )
      expect_any_instance_of(Admin::Maintenance::Platform::Billing::CountableItemsController).to receive(:render)
        .with(:show, status: :unprocessable_entity).and_wrap_original do |original, *args, **kwargs|
          expect(original.receiver.instance_variable_get(:@form)).to equal(form)
          expect(original.receiver.instance_variable_get(:@submitted_items).first["position"]).to eq("broken")
          original.call(*args, **kwargs)
        end
      patch guard_path, params: { items: [{ id: item.id, label: "Submitted", position: "broken", period: "total" }] }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(item.reload.label).to eq("Pages")
    end

    it "requires the valid platform URL for owner writes" do
      expect(Billing::Catalog::UpdateCountableItems).not_to receive(:call)
      patch admin_maintenance_platform_billing_countable_items_path(create(:customer).id),
            params: { items: [] }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
