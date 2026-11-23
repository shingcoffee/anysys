# frozen_string_literal: true

require "rails_helper"

# Tenant maintenance vs Shared Resources write targeting for Pages, Flowcharts,
# and Constants — same URL rule as shared entities.
RSpec.describe "Shared resource per-customer overrides", type: :request do
  include_context "as platform owner"

  let(:platform_cid) { customer.id }
  let(:other) { create(:customer) }

  describe "PATCH platform page — auth guards" do
    let!(:shared) { create(:page, :shared, name: "GuardOverridePage") }
    let(:guard_path) { "/#{platform_cid}/admin/maintenance/platform/pages/#{shared.id}" }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "PATCH platform flowchart — auth guards" do
    let!(:shared) { create(:flowchart, :shared_type, :draft, name: "GuardOverrideFlow") }
    let(:guard_path) { "/#{platform_cid}/admin/maintenance/platform/flowcharts/#{shared.id}" }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "PATCH platform constant — auth guards" do
    let!(:shared) { create(:constant, :shared, name: "GuardOverrideConst", options: %w[Red]) }
    let(:guard_path) { "/#{platform_cid}/admin/maintenance/platform/constants/#{shared.id}" }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "DELETE page override — auth guards" do
    let!(:shared) { create(:page, :shared, name: "GuardResetPage") }
    let(:guard_path) { "/#{platform_cid}/admin/maintenance/pages/#{shared.id}/override" }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  describe "DELETE flowchart override — auth guards" do
    let!(:shared) { create(:flowchart, :shared_type, :draft, name: "GuardResetFlow") }
    let(:guard_path) { "/#{platform_cid}/admin/maintenance/flowcharts/#{shared.id}/override" }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  describe "DELETE constant override — auth guards" do
    let!(:shared) { create(:constant, :shared, name: "GuardResetConst", options: %w[Red]) }
    let(:guard_path) { "/#{platform_cid}/admin/maintenance/constants/#{shared.id}/override" }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  describe "pages" do
    let!(:shared) { create(:page, :shared, name: "SharedLanding") }

    def config_with_title(page, title)
      config = JSON.parse(page.configuration)
      config["pages"] ||= [{ "id" => "page_1", "name" => "Page 1", "order" => 1, "fields" => [] }]
      config["pages"][0]["name"] = title
      config.to_json
    end

    it "writes an 81721200 override from tenant maintenance and ignores name" do
      patch "/#{platform_cid}/admin/maintenance/pages/#{shared.id}",
            params: {
              page: {
                name: "Hacked",
                configuration: config_with_title(shared, "Owner Tenant Page"),
                updated_at: shared.updated_at.iso8601(6)
              }
            }
      expect(response).to have_http_status(:found)
      expect(PageCustomerHead.find_by(page_id: shared.id, customer_id: platform_cid)).to be_present
      expect(shared.reload.name).to eq("SharedLanding")
      Current.with_customer(nil) do
        expect(JSON.parse(Page.find(shared.id).configuration).dig("pages", 0, "name")).not_to eq("Owner Tenant Page")
      end
      Current.with_customer(customer) do
        expect(JSON.parse(Page.find(shared.id).configuration).dig("pages", 0, "name")).to eq("Owner Tenant Page")
      end
    end

    it "advances the global default from Shared Resources" do
      patch "/#{platform_cid}/admin/maintenance/platform/pages/#{shared.id}",
            params: {
              page: {
                name: "Renamed Global",
                configuration: config_with_title(shared, "Owner Platform Page"),
                updated_at: shared.updated_at.iso8601(6)
              }
            }
      expect(response).to have_http_status(:found)
      expect(PageCustomerHead.where(page_id: shared.id)).to be_empty
      expect(shared.reload.name).to eq("Renamed Global")
      Current.with_customer(other) do
        expect(JSON.parse(Page.find(shared.id).configuration).dig("pages", 0, "name")).to eq("Owner Platform Page")
      end
    end

    it "resets the tenant override so reads fall back to the global default" do
      patch "/#{platform_cid}/admin/maintenance/pages/#{shared.id}",
            params: {
              page: {
                configuration: config_with_title(shared, "Owner Tenant Page"),
                updated_at: shared.updated_at.iso8601(6)
              }
            }
      delete "/#{platform_cid}/admin/maintenance/pages/#{shared.id}/override"
      expect(response).to have_http_status(:found)
      expect(PageCustomerHead.find_by(page_id: shared.id, customer_id: platform_cid)).to be_nil
      Current.with_customer(customer) do
        expect(JSON.parse(Page.find(shared.id).configuration).dig("pages", 0, "name")).not_to eq("Owner Tenant Page")
      end
    end

    it "keeps another tenant on the global default when this customer overrides" do
      patch "/#{platform_cid}/admin/maintenance/pages/#{shared.id}",
            params: {
              page: {
                configuration: config_with_title(shared, "Owner Tenant Page"),
                updated_at: shared.updated_at.iso8601(6)
              }
            }
      Current.with_customer(other) do
        expect(JSON.parse(Page.find(shared.id).configuration).dig("pages", 0, "name")).not_to eq("Owner Tenant Page")
      end
    end

    it "404s when resetting a customer-owned page" do
      owned = create(:page, customer: customer, name: "OwnedLanding")
      delete "/#{platform_cid}/admin/maintenance/pages/#{owned.id}/override"
      expect(response).to have_http_status(:not_found)
    end

    it "flashes an alert when no override exists to revert" do
      delete "/#{platform_cid}/admin/maintenance/pages/#{shared.id}/override"
      expect(response).to have_http_status(:found)
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.shared_resources.override_missing"))
      expect(flash[:notice]).to be_nil
    end
  end

  describe "flowcharts" do
    let!(:shared) { create(:flowchart, :shared_type, :draft, name: "SharedFlow") }

    def config_with_label(flowchart, label)
      config = JSON.parse(flowchart.configuration)
      config["elements"][1]["label"] = label
      config.to_json
    end

    it "writes an 81721200 override from tenant maintenance and ignores name" do
      patch "/#{platform_cid}/admin/maintenance/flowcharts/#{shared.id}",
            params: {
              flowchart: {
                name: "Hacked",
                configuration: config_with_label(shared, "Owner Tenant Step")
              }
            }
      expect(response).to have_http_status(:found)
      expect(FlowchartCustomerHead.find_by(flowchart_id: shared.id, customer_id: platform_cid)).to be_present
      expect(shared.reload.name).to eq("SharedFlow")
      Current.with_customer(nil) do
        expect(JSON.parse(Flowchart.find(shared.id).configuration).dig("elements", 1, "label")).not_to eq("Owner Tenant Step")
      end
      Current.with_customer(customer) do
        expect(JSON.parse(Flowchart.find(shared.id).configuration).dig("elements", 1, "label")).to eq("Owner Tenant Step")
      end
    end

    it "writes a tenant override of a launched shared flowchart without taking it offline" do
      shared.update_column(:status, Flowchart.statuses[:launched])
      patch "/#{platform_cid}/admin/maintenance/flowcharts/#{shared.id}",
            params: {
              flowchart: {
                configuration: config_with_label(shared, "Launched Tenant Step")
              }
            }
      expect(response).to have_http_status(:found)
      expect(shared.reload.status).to eq("launched")
      expect(FlowchartCustomerHead.find_by(flowchart_id: shared.id, customer_id: platform_cid)).to be_present
      Current.with_customer(customer) do
        expect(JSON.parse(Flowchart.find(shared.id).configuration).dig("elements", 1, "label")).to eq("Launched Tenant Step")
      end
    end

    it "advances the global default from Shared Resources" do
      patch "/#{platform_cid}/admin/maintenance/platform/flowcharts/#{shared.id}",
            params: {
              flowchart: {
                name: "Renamed Flow",
                configuration: config_with_label(shared, "Owner Platform Step")
              }
            }
      expect(response).to have_http_status(:found)
      expect(FlowchartCustomerHead.where(flowchart_id: shared.id)).to be_empty
      expect(shared.reload.name).to eq("Renamed Flow")
      Current.with_customer(other) do
        expect(JSON.parse(Flowchart.find(shared.id).configuration).dig("elements", 1, "label")).to eq("Owner Platform Step")
      end
    end

    it "resets the tenant override so reads fall back to the global default" do
      patch "/#{platform_cid}/admin/maintenance/flowcharts/#{shared.id}",
            params: { flowchart: { configuration: config_with_label(shared, "Owner Tenant Step") } }
      delete "/#{platform_cid}/admin/maintenance/flowcharts/#{shared.id}/override"
      expect(response).to have_http_status(:found)
      expect(FlowchartCustomerHead.find_by(flowchart_id: shared.id, customer_id: platform_cid)).to be_nil
      Current.with_customer(customer) do
        expect(JSON.parse(Flowchart.find(shared.id).configuration).dig("elements", 1, "label")).not_to eq("Owner Tenant Step")
      end
    end

    it "404s when resetting a customer-owned flowchart" do
      entity = create(:entity, customer: customer)
      owned = create(:flowchart, :draft, customer: customer)
      delete "/#{platform_cid}/admin/maintenance/flowcharts/#{owned.id}/override"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "constants" do
    let!(:shared) { create(:constant, :shared, name: "SharedColors", options: %w[Red Blue]) }

    it "writes an 81721200 override from tenant maintenance and ignores name" do
      patch "/#{platform_cid}/admin/maintenance/constants/#{shared.id}",
            params: { constant: { name: "Hacked", options: '["Green"]' } }
      expect(response).to have_http_status(:found)
      expect(shared.reload.name).to eq("SharedColors")
      Current.with_customer(nil) { expect(Constant.find(shared.id).options).to eq(%w[Red Blue]) }
      ov = ConstantCustomerOverride.find_by(constant_id: shared.id, customer_id: platform_cid)
      expect(ov.options).to eq(%w[Green])
    end

    it "advances the global default from Shared Resources" do
      patch "/#{platform_cid}/admin/maintenance/platform/constants/#{shared.id}",
            params: { constant: { name: "Renamed Colors", options: '["Green"]' } }
      expect(response).to have_http_status(:found)
      expect(shared.reload.name).to eq("Renamed Colors")
      expect(shared.reload.options).to eq(%w[Green])
      expect(ConstantCustomerOverride.where(constant_id: shared.id)).to be_empty
    end

    it "resets the tenant override so reads fall back to the global default" do
      patch "/#{platform_cid}/admin/maintenance/constants/#{shared.id}",
            params: { constant: { options: '["Green"]' } }
      delete "/#{platform_cid}/admin/maintenance/constants/#{shared.id}/override"
      expect(response).to have_http_status(:found)
      expect(ConstantCustomerOverride.find_by(constant_id: shared.id, customer_id: platform_cid)).to be_nil
      Current.with_customer(customer) { expect(Constant.find(shared.id).options).to eq(%w[Red Blue]) }
    end

    it "keeps another tenant on the global default when this customer overrides" do
      patch "/#{platform_cid}/admin/maintenance/constants/#{shared.id}",
            params: { constant: { options: '["Green"]' } }
      Current.with_customer(other) { expect(Constant.find(shared.id).options).to eq(%w[Red Blue]) }
    end

    it "404s when resetting a customer-owned constant" do
      owned = create(:constant, customer: customer, name: "OwnedColors", options: %w[Red])
      delete "/#{platform_cid}/admin/maintenance/constants/#{owned.id}/override"
      expect(response).to have_http_status(:not_found)
    end
  end
end
