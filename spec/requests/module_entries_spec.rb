# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard module entries", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer, role: :admin) }
  let(:admin)    { user }
  let(:guard_path) { "/#{customer.id}/admin/modules/payments/entries/transactions" }

  it_behaves_like "an admin-guarded GET"

  before do
    sign_in user
    enable_module!("payment", customer, name: "Payments")
  end

  it "renders the standard entries table for an enabled module" do
    get "/#{customer.id}/admin/modules/payments/entries/transactions"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Transactions")
  end

  it "404s when the module is not enabled for the customer" do
    other = create(:customer)
    user2 = create(:user, customer: other, role: :admin)
    sign_in user2
    get "/#{other.id}/admin/modules/payments/entries/transactions"
    expect(response).to have_http_status(:not_found)
  end

  describe "GET sms messages entries — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/modules/sms/entries/messages" }

    before { enable_module!("sms", customer, name: "SMS") }

    it_behaves_like "an admin-guarded GET"

    it "renders the SMS messages entries table" do
      get guard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("feature_modules.sms.titles.messages"))
    end
  end

  describe "GET email templates entries — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/modules/emails/entries/templates" }

    before { enable_module!("email", customer, name: "Email") }

    it_behaves_like "an admin-guarded GET"

    it "renders the email templates entries table" do
      get guard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("feature_modules.email.titles.templates"))
    end
  end

  describe "GET email send_activities entries — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/modules/emails/entries/send_activities" }

    before { enable_module!("email", customer, name: "Email") }

    it_behaves_like "an admin-guarded GET"

    it "renders the send activities entries table" do
      get guard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("feature_modules.email.titles.send_activities"))
    end
  end

  describe "GET email lists entries — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/modules/emails/entries/lists" }

    before { enable_module!("email", customer, name: "Email") }

    it_behaves_like "an admin-guarded GET"

    it "renders the lists entries table" do
      get guard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("feature_modules.email.titles.lists"))
    end
  end

  it "404s for an unknown entry_key instead of raising" do
    get "/#{customer.id}/admin/modules/payments/entries/not_a_real_entry"
    expect(response).to have_http_status(:not_found)
  end
end
