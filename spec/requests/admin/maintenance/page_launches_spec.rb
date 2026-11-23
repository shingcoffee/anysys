# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::PageLaunches", type: :request do
  let(:customer)     { create(:customer) }
  let(:admin)        { create(:user, :admin, customer: customer) }
  # A page with an entity and at least one field so launch_errors is empty.
  let!(:entity)      { create(:entity, customer: customer) }
  let!(:page_record) { create(:page, customer: customer, entity: entity) }

  def launch_path(page = page_record) = "/#{customer.id}/admin/maintenance/pages/#{page.id}/launch"

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "POST create — auth guards" do
    let(:guard_path) { launch_path }

    it_behaves_like "an admin-guarded request", :post
  end

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { launch_path }

    it_behaves_like "an admin-guarded request", :delete
  end

  # ---------------------------------------------------------------------------
  # POST create — launch errors present
  # ---------------------------------------------------------------------------

  describe "POST create — bound entity is trashed" do
    before { sign_in admin }

    it "does not launch and flashes the missing-or-deleted error" do
      config = page_record.configuration_json
      config["pages"] = [{ "id" => "p1", "name" => "Page 1", "order" => 1, "fields" => [
        { "id" => "f1", "label" => "Name", "property_type" => "string" }
      ] }]
      page_record.configuration_json = config
      page_record.save!(validate: false)
      entity.soft_delete

      post launch_path

      expect(response).to have_http_status(:redirect)
      expect(page_record.reload.launched).to be(false)
      expect(flash[:alert]).to include(I18n.t("maint_core.errors.page_launch.entity_missing"))
    end
  end

  describe "POST create — page has launch errors" do
    before do
      sign_in admin
      # Stub launch_errors to return a non-empty list.
      allow_any_instance_of(Page).to receive(:launch_errors).and_return(["page has no fields"])
    end

    it "redirects to the edit page with an alert and does not launch the page" do
      post launch_path

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/can't launch/i)
      expect(page_record.reload.launched).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — happy path
  # ---------------------------------------------------------------------------

  describe "POST create — page is launchable" do
    before do
      sign_in admin
      allow_any_instance_of(Page).to receive(:launch_errors).and_return([])
    end

    it "launches the page and redirects to its detail page" do
      post launch_path

      expect(response).to have_http_status(:redirect)
      expect(page_record.reload.launched).to be(true)
      expect(flash[:notice]).to match(/launched successfully/i)
    end

    it "honors a safe return_to path" do
      return_to = "/#{customer.id}/admin/pages/#{page_record.id}"
      post launch_path, params: { return_to: return_to }

      expect(response).to redirect_to(return_to)
      expect(page_record.reload.launched).to be(true)
    end

    it "ignores an absolute return_to URL" do
      post launch_path, params: { return_to: "https://evil.example/phish" }

      expect(response).to redirect_to(admin_maintenance_page_path(customer.id, page_record))
    end

    it "ignores a backslash protocol-relative return_to" do
      post launch_path, params: { return_to: "/\\evil.example/phish" }

      expect(response).to redirect_to(admin_maintenance_page_path(customer.id, page_record))
    end

    it "ignores a cross-tenant return_to path" do
      other = create(:customer)
      post launch_path, params: { return_to: "/#{other.id}/admin/pages/#{page_record.id}" }

      expect(response).to redirect_to(admin_maintenance_page_path(customer.id, page_record))
    end

    it "ignores a same-tenant return_to that walks out with .." do
      other = create(:customer)
      post launch_path, params: { return_to: "/#{customer.id}/admin/../../../#{other.id}/admin" }

      expect(response).to redirect_to(admin_maintenance_page_path(customer.id, page_record))
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy — take a launched page offline
  # ---------------------------------------------------------------------------

  describe "DELETE destroy — take page offline" do
    before do
      sign_in admin
      page_record.update_column(:launched, true)
    end

    it "takes the page offline and redirects" do
      delete launch_path

      expect(response).to have_http_status(:redirect)
      expect(page_record.reload.launched).to be(false)
      expect(flash[:notice]).to match(/taken offline/i)
    end

    it "honors a safe return_to path when taking offline" do
      return_to = "/#{customer.id}/admin/pages/#{page_record.id}"
      delete launch_path, params: { return_to: return_to }

      expect(response).to redirect_to(return_to)
      expect(page_record.reload.launched).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "cross-tenant isolation" do
    let(:other_customer) { create(:customer) }
    let!(:other_page)    { create(:page, customer: other_customer) }

    before { sign_in admin }

    it "returns 404 for another tenant's page on POST" do
      post launch_path(other_page)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for another tenant's page on DELETE" do
      delete launch_path(other_page)
      expect(response).to have_http_status(:not_found)
    end
  end
end
