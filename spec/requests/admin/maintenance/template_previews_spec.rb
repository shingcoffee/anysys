# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::TemplatePreviews", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  # A real template key that exists in PageLayoutTemplates.
  let(:valid_key) { "job_application" }

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "GET show — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/template_previews/#{valid_key}" }

    it_behaves_like "an admin-guarded GET"
  end

  # ---------------------------------------------------------------------------
  # GET show — happy path
  # ---------------------------------------------------------------------------

  describe "GET show — valid template key" do
    before { sign_in admin }

    it "returns 200 rendered with the template_preview layout" do
      get "/#{customer.id}/admin/maintenance/template_previews/#{valid_key}"
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # GET show — unknown template key redirects with an alert
  # ---------------------------------------------------------------------------

  describe "GET show — unknown template key" do
    before { sign_in admin }

    it "redirects to the entities index with an alert" do
      get "/#{customer.id}/admin/maintenance/template_previews/bogus_key_xyz_999"

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to match(/template not found/i)
    end
  end
end
