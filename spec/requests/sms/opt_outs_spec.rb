# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sms::Admin::OptOuts", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:owner) { create(:user, :admin, customer: customer, password: "password123") }
  let(:admin) { owner }

  let(:index_path) { "/#{customer.id}/admin/modules/sms/opt_outs" }
  let(:guard_path) { index_path }

  it_behaves_like "an admin-guarded GET"

  before do
    Current.customer = customer
    sign_in owner
  end

  it "GET index renders this tenant's manual opt-out row" do
    Sms::OptOut.record_for_customer!(customer_id: customer.id, phone_e164: "+8613800138000", reason: "manual")

    get index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("+8613800138000")
  end

  it "GET index renders a GLOBAL opt-out row only for a number this tenant has messaged" do
    Sms::OptOut.record_global!(phone_e164: "+8613800139999", provider: "twilio", reason: "inbound:STOP")
    # This tenant actually texted that number, so it may see the global opt-out.
    create(:sms_message, customer: customer, to: "+8613800139999", status: "sent", sent_at: Time.current)

    get index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("+8613800139999")
  end

  it "hides a GLOBAL opt-out for a number this tenant never messaged (no cross-tenant PII leak)" do
    # A number that only OTHER tenants texted must not be enumerable here.
    Sms::OptOut.record_global!(phone_e164: "+8613800135555", provider: "twilio", reason: "inbound:STOP")

    get index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("+8613800135555")
  end

  it "does not leak another tenant's manual opt-out row" do
    other = create(:customer)
    Sms::OptOut.record_for_customer!(customer_id: other.id, phone_e164: "+8613800137777", reason: "manual")

    get index_path
    expect(response.body).not_to include("+8613800137777")
  end

  %w[pending failed unknown suppressed].each do |status|
    it "does not expose a global opt-out merely because a #{status} send was attempted" do
      Sms::OptOut.record_global!(phone_e164: "+8613800134444", provider: "twilio", reason: "inbound:STOP")
      create(:sms_message, customer: customer, to: "+8613800134444", status: status, sent_at: nil)

      get index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("+8613800134444")
    end
  end

  it "still exposes the opt-out after a previously sent message receives a failure receipt" do
    Sms::OptOut.record_global!(phone_e164: "+8613800133333", provider: "twilio", reason: "inbound:STOP")
    create(:sms_message, customer: customer, to: "+8613800133333", status: "failed", sent_at: 1.day.ago)

    get index_path

    expect(response.body).to include("+8613800133333")
  end
end
