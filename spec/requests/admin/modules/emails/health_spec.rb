# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Emails::Health", type: :request do
  include_context "as admin"
  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let(:guard_path) { "/#{customer.id}/admin/modules/emails/health" }

  it_behaves_like "an admin-guarded GET"

  describe "GET /:customer_id/admin/modules/emails/health" do
    %w[en zh-CN].each do |locale|
      it "renders a scalar device heading and translated device labels in #{locale}" do
        message = create(:email_message, customer: customer, status: "delivered", created_at: 1.day.ago)
        create(:email_message_event, message: message, event_type: "open",
               user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X)", occurred_at: 1.day.ago)

        get "/#{customer.id}/admin/modules/emails/health", params: { locale: locale }

        expect(response).to have_http_status(:ok)
        expect(Capybara.string(response.body)).to have_css(
          "h3", text: I18n.t("admin_modules.emails.analytics.engagement.devices_heading", locale: locale)
        )
        expect(response.body).to include(I18n.t("admin_modules.emails.analytics.engagement.devices.desktop", locale: locale))
        expect(response.body).not_to include("translation missing")
      end
    end

    it "renders the health analytics surface" do
      get "/#{customer.id}/admin/modules/emails/health"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("feature_modules.email.tabs.health"))
      expect(response.body).to include(I18n.t("admin_modules.emails.analytics.health.description"))
    end

    it "does not 500 when since and until are arrays" do
      get "/#{customer.id}/admin/modules/emails/health", params: { since: ["2020-01-01"], until: ["2020-12-31"] }

      expect(response).to have_http_status(:success)
    end

    it "does not 500 when reason is a nested hash" do
      get "/#{customer.id}/admin/modules/emails/health", params: { reason: { foo: "bar" } }

      expect(response).to have_http_status(:success)
    end

    it "does not expand a millennia-wide since/until into a 500 or memory bomb" do
      get "/#{customer.id}/admin/modules/emails/health",
          params: { since: "0001-01-01", until: "9999-12-31" }

      expect(response).to have_http_status(:success)
    end

    it "renders health data for the current customer only" do
      create(:email_message, customer: customer, status: "bounced", failure_code: "SMTP_ERROR", created_at: 1.day.ago)
      Emails::Suppression.create!(customer_id: customer.id, email: "tenant@example.com", reason: "hard_bounce")
      message = create(:email_message, customer: customer, status: "delivered", created_at: 1.day.ago)
      Emails::MessageEvent.create!(message: message, event_type: "click", url: "https://tenant.example.com", occurred_at: 1.day.ago)

      other_customer = create(:customer)
      create(:email_message, customer: other_customer, status: "bounced", failure_code: "OTHER_ERROR", created_at: 1.day.ago)

      get "/#{customer.id}/admin/modules/emails/health"

      expect(response.body).to include("SMTP_ERROR")
      expect(response.body).to include("tenant@example.com")
      expect(response.body).to include("https://tenant.example.com")
      expect(response.body).not_to include("OTHER_ERROR")
    end

    it "renders failed delivery ledger codes without exposing another tenant's failure" do
      create(:email_message, customer: customer, status: "failed", failure_code: "OWN_SEND_FAILURE", created_at: 1.day.ago)
      create(:email_message, customer: create(:customer), status: "failed", failure_code: "FOREIGN_SEND_FAILURE", created_at: 1.day.ago)

      get "/#{customer.id}/admin/modules/emails/health"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("OWN_SEND_FAILURE")
      expect(response.body).not_to include("FOREIGN_SEND_FAILURE")
    end
  end
end
