# frozen_string_literal: true

require "rails_helper"

# Admin::Maintenance::PageCopiesController
#
# Serves GET /:cid/admin/maintenance/pages/:page_id/copy — renders the page
# "new" form pre-filled from an existing page ("Copy of <name>"). The copy
# resource nests under `resources :pages`, so the parent id arrives as
# params[:page_id]; the controller overrides the inherited find_page to read
# that param.

RSpec.describe "Admin::Maintenance::PageCopies", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let!(:page_record) { create(:page, customer: customer, name: "Contact Form") }

  def copy_path(page = page_record) = "/#{customer.id}/admin/maintenance/pages/#{page.id}/copy"

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "GET show — auth guards" do
    let(:guard_path) { copy_path }

    it_behaves_like "an admin-guarded GET"
  end

  # ---------------------------------------------------------------------------
  # Happy path — admin copies a page
  # ---------------------------------------------------------------------------

  describe "GET show — admin copies a page" do
    before { sign_in admin }

    it "renders the new-page form pre-filled with a 'Copy of <name>' page" do
      get copy_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Copy of Contact Form")
    end

    it "does not persist a new page (renders an unsaved copy)" do
      expect {
        get copy_path
      }.not_to change(Page, :count)
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "GET show — shared page is not copy-to-customer" do
    let!(:shared_page) { create(:page, :shared, name: "Global Page") }

    before { sign_in admin }

    it "returns 404" do
      get copy_path(shared_page)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET show — cross-tenant access is forbidden" do
    let(:other_customer) { create(:customer) }
    let!(:other_page)    { create(:page, customer: other_customer) }

    before { sign_in admin }

    it "returns 404 for another tenant's page" do
      get copy_path(other_page)
      expect(response).to have_http_status(:not_found)
    end
  end
end
