# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::TemplatePickerCards", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  describe "GET show" do
    let(:guard_path) { "/#{customer.id}/admin/maintenance/template_picker_cards" }

    it_behaves_like "an admin-guarded GET"

    it "renders template cards for an admin (scope=all) and honours scope=industry" do
      sign_in admin
      get "/#{customer.id}/admin/maintenance/template_picker_cards", params: { scope: "all" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-template-key")
      # No application layout when rendered for injection
      expect(response.body).not_to include("<html")

      get "/#{customer.id}/admin/maintenance/template_picker_cards", params: { scope: "industry" }
      expect(response).to have_http_status(:ok)
    end
  end
end
