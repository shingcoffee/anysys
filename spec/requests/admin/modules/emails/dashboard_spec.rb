require "rails_helper"

RSpec.describe "Admin::Modules::Emails::Dashboard", type: :request do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let(:guard_path) { "/#{customer.id}/admin/modules/emails/dashboard" }

  before { sign_in admin }

  it_behaves_like "an admin-guarded GET"

  describe "GET /:customer_id/admin/modules/emails/dashboard.csv" do
    let(:guard_path) { "/#{customer.id}/admin/modules/emails/dashboard.csv" }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET /:customer_id/admin/modules/emails/dashboard" do
    it "renders the Overview analytics surface" do
      get "/#{customer.id}/admin/modules/emails/dashboard"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("feature_modules.email.tabs.overview"))
      expect(response.body).to include(I18n.t("feature_modules.email.tabs.health"))
    end

    it "does not 500 when since and until are arrays" do
      get "/#{customer.id}/admin/modules/emails/dashboard", params: { since: ["2020-01-01"], until: ["2020-12-31"] }

      expect(response).to have_http_status(:success)
    end

    it "does not expand a millennia-wide since/until into a 500 or memory bomb" do
      get "/#{customer.id}/admin/modules/emails/dashboard",
          params: { since: "0001-01-01", until: "9999-12-31" }

      expect(response).to have_http_status(:success)
    end

    it "exports analytics CSV" do
      create(:email_message, customer: customer, status: "delivered", created_at: 1.day.ago)

      get "/#{customer.id}/admin/modules/emails/dashboard.csv"

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/csv")
    end

    it "does not dump every matching message on the CSV export" do
      stub_const("Emails::Analytics::ExportCsv::MAX_ROWS", 2)
      create(:email_message, customer: customer, to: "aaa@example.com", created_at: 3.days.ago)
      create(:email_message, customer: customer, to: "bbb@example.com", created_at: 2.days.ago)
      create(:email_message, customer: customer, to: "ccc@example.com", created_at: 1.day.ago)

      get "/#{customer.id}/admin/modules/emails/dashboard.csv"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("ccc@example.com")
      expect(response.body).to include("bbb@example.com")
      expect(response.body).not_to include("aaa@example.com")
    end
  end
end
