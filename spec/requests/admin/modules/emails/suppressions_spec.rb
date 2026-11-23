# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Emails::Suppressions", type: :request do
  include_context "as admin"

  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let(:other_customer) { create(:customer) }
  let(:base_path)       { "/#{customer.id}/admin/modules/emails/suppressions" }

  describe "GET /:cid/admin/modules/emails/suppressions" do
    let(:guard_path) { base_path }

    it_behaves_like "an admin-guarded GET"
    it "titles the page Suppressions under Audience" do
      get admin_modules_emails_suppressions_path(customer)

      expect(response.body).to include(I18n.t("feature_modules.email.tabs.suppressions"))
      expect(response.body).to include(I18n.t("feature_modules.email.entries.audience"))
      expect(response.body).not_to match(/<h1[^>]*>\s*#{Regexp.escape(I18n.t("feature_modules.email.entries.settings"))}\s*<\/h1>/)
    end

    it "renders the tenant's own manual suppression" do
      Emails::Suppression.record_for_customer!(customer_id: customer.id, email: "own-manual@example.com", reason: "manual")

      get base_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("own-manual@example.com")
    end

    it "does not render global suppressions" do
      Emails::Suppression.record_global!(email: "global-bounce@example.com", reason: "hard_bounce", provider: "ses")

      get base_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("global-bounce@example.com")
    end

    it "does not expose another customer's tenant-scoped suppression" do
      Emails::Suppression.record_for_customer!(customer_id: other_customer.id, email: "other-only@example.com", reason: "manual")

      get base_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("other-only@example.com")
    end

    it "redirects a cross-tenant admin away from another tenant's admin URL entirely" do
      other_admin = create(:user, :admin, customer: other_customer)

      sign_out admin
      sign_in other_admin
      get base_path

      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "filters by reason" do
      Emails::Suppression.record_for_customer!(customer_id: customer.id, email: "manual@example.com", reason: "manual")
      Emails::Suppression.record_for_customer!(customer_id: customer.id, email: "bounce@example.com", reason: "hard_bounce")

      get base_path, params: { reason: "manual" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("manual@example.com")
      expect(response.body).not_to include("bounce@example.com")
    end

    it "filters by provider" do
      Emails::Suppression.record_for_customer!(customer_id: customer.id, email: "ses@example.com", reason: "hard_bounce", provider: "ses")
      Emails::Suppression.record_for_customer!(customer_id: customer.id, email: "sendgrid@example.com", reason: "hard_bounce", provider: "sendgrid")

      get base_path, params: { provider: "ses" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ses@example.com")
      expect(response.body).not_to include("sendgrid@example.com")
    end

    it "does not 500 when reason or provider is a nested hash" do
      Emails::Suppression.record_for_customer!(customer_id: customer.id, email: "kept@example.com", reason: "manual")

      get base_path, params: { reason: { foo: "bar" }, provider: { foo: "bar" } }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("kept@example.com")
    end
  end

  describe "DELETE /:cid/admin/modules/emails/suppressions/batch_unblock" do
    let(:guard_path) { "#{base_path}/batch_unblock" }

    it_behaves_like "an admin-guarded request", :delete
    it "removes selected tenant-scoped suppressions" do
      suppression = Emails::Suppression.record_for_customer!(customer_id: customer.id, email: "manual@example.com", reason: "manual")

      delete "#{base_path}/batch_unblock", params: { suppression_ids: [suppression.id] }

      expect(response).to redirect_to(base_path)
      follow_redirect!
      expect(response.body).to include("Selected suppressions removed")
      expect(Emails::Suppression.exists?(suppression.id)).to be false
    end

    it "returns 404 when the Email module is disabled" do
      suppression = Emails::Suppression.record_for_customer!(customer_id: customer.id, email: "manual@example.com", reason: "manual")
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: email_module
      ).update!(status: :suspended)

      delete "#{base_path}/batch_unblock", params: { suppression_ids: [suppression.id] }

      expect(response).to have_http_status(:not_found)
      expect(Emails::Suppression.exists?(suppression.id)).to be true
    end

    it "does not remove global suppressions" do
      suppression = Emails::Suppression.record_global!(email: "global@example.com", reason: "hard_bounce", provider: "ses")

      delete "#{base_path}/batch_unblock", params: { suppression_ids: [suppression.id] }

      expect(response).to redirect_to(base_path)
      expect(Emails::Suppression.exists?(suppression.id)).to be true
    end

    it "does not remove another tenant's suppression" do
      suppression = Emails::Suppression.record_for_customer!(customer_id: other_customer.id, email: "other@example.com", reason: "manual")

      delete "#{base_path}/batch_unblock", params: { suppression_ids: [suppression.id] }

      expect(response).to redirect_to(base_path)
      expect(Emails::Suppression.exists?(suppression.id)).to be true
    end

    it "does not 500 when suppression_ids is a nested hash" do
      suppression = Emails::Suppression.record_for_customer!(customer_id: customer.id, email: "kept@example.com", reason: "manual")

      delete "#{base_path}/batch_unblock", params: { suppression_ids: { foo: suppression.id } }

      expect(response).to redirect_to(base_path)
      expect(Emails::Suppression.exists?(suppression.id)).to be true
    end
  end
end
