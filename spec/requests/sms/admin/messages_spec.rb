# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sms::Admin::Messages", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:owner)    { create(:user, :admin, customer: customer, password: "password123") }
  let(:admin) { owner }
  let(:guard_path) { "/#{customer.id}/admin/modules/sms/messages" }

  it_behaves_like "an admin-guarded GET"

  describe "GET show — auth guards" do
    let!(:msg) do
      create(:sms_message, customer: customer, to: "+8613800138000",
             template_key: "verify_code", status: "sent")
    end
    let(:guard_path) { "/#{customer.id}/admin/modules/sms/messages/#{msg.id}" }

    it_behaves_like "an admin-guarded GET"
  end

  before do
    Current.customer = customer
    sign_in owner
  end

  # Creates a message owned by a different tenant, restoring Current.customer.
  def create_other_tenant_message
    other = create(:customer)
    Current.customer = other
    msg = create(:sms_message, customer: other, to: "+8613800139999", template_key: "verify_code")
    Current.customer = customer
    msg
  end

  it "GET index renders the messages table" do
    create(:sms_message, customer: customer, to: "+8613800138000",
           template_key: "verify_code", status: "sent")
    get "/#{customer.id}/admin/modules/sms/messages"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("+8613800138000")
    expect(response.body).to include("verify_code")
    expect(response.body).to include("sent")
  end

  %w[en zh-CN].each do |locale|
    it "GET index translates an expired message badge in #{locale}" do
      msg = create(:sms_message, customer: customer, to: "+8613800138000", status: "expired")

      get guard_path, params: { locale: locale }

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      row = document.css("tbody tr").find { |entry| entry.text.include?(msg.to) }
      expect(row).to be_present
      expect(row.at_css("td:nth-child(3)").text.strip).to eq(I18n.t("sms.statuses.expired", locale: locale))
      expect(response.body).not_to include("translation_missing", "translation missing", "common.status.expired")
    end
  end

  it "GET show renders the message detail" do
    msg = create(:sms_message, customer: customer, to: "+8613800138000",
                 template_key: "verify_code", status: "sent",
                 vars: { "code" => "secret-654321", "email" => "private@example.test" })
    get "/#{customer.id}/admin/modules/sms/messages/#{msg.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("SMS Message ##{msg.id}")
    expect(response.body).to include("Sent")
    expect(response.body).to include("The provider accepted this message. This does not confirm delivery to the recipient.")
    expect(response.body).to include("Redacted", "code", "email")
    expect(response.body).not_to include("secret-654321", "private@example.test")
  end

  it "GET show renders recorded provider facts and zero attempts without estimating absent facts" do
    msg = create(:sms_message, customer: customer, status: "queued", delivery_attempts: 0,
                 metadata: { "provider_status" => "queued", "provider_segments" => 2 })
    get "/#{customer.id}/admin/modules/sms/messages/#{msg.id}"
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(".card > dl")[:class]).to include("grid-cols-1", "md:grid-cols-2")
    expect(document.at_xpath("//dt[text()='Delivery attempts']/following-sibling::dd").text.strip).to eq("0")
    expect(document.at_xpath("//dt[text()='Provider-reported segments']/following-sibling::dd").text.strip).to eq("2")
    expect(document.at_xpath("//dt[text()='Expires at']/following-sibling::dd").text.strip).to eq("Unknown")
    expect(response.body).not_to include("translation_missing")
  end

  it "GET show localizes expiry and redaction in zh-CN without leaking variable values" do
    msg = create(:sms_message, customer: customer, status: "expired", vars: { "code" => "secret-expired-code" })
    get "/#{customer.id}/admin/modules/sms/messages/#{msg.id}", params: { locale: "zh-CN" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("sms.statuses.expired", locale: :"zh-CN"))
    expect(response.body).to include(I18n.t("sms_presentation.redacted", locale: :"zh-CN"))
    expect(response.body).not_to include("secret-expired-code", "translation_missing")
  end

  it "GET show localizes sent_at and delivered_at instead of ISO strftime" do
    sent_at = Time.zone.local(2026, 6, 15, 10, 30, 0)
    delivered_at = Time.zone.local(2026, 6, 15, 10, 31, 0)
    msg = create(:sms_message, customer: customer, to: "+8613800138000",
                 template_key: "verify_code", status: "delivered",
                 sent_at: sent_at, delivered_at: delivered_at)
    get "/#{customer.id}/admin/modules/sms/messages/#{msg.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.l(sent_at, format: :long))
    expect(response.body).to include(I18n.l(delivered_at, format: :long))
    expect(response.body).not_to include(sent_at.strftime("%Y-%m-%d %H:%M:%S"))
  end

  it "GET show localizes timestamps in zh-CN" do
    sent_at = Time.zone.local(2026, 6, 15, 10, 30, 0)
    msg = create(:sms_message, customer: customer, to: "+8613800138000",
                 template_key: "verify_code", status: "sent", sent_at: sent_at)
    get "/#{customer.id}/admin/modules/sms/messages/#{msg.id}", params: { locale: "zh-CN" }
    expect(response.body).to include(I18n.l(sent_at, format: :long, locale: :"zh-CN"))
  end

  it "GET show translates a canned failure key and uses the shared em-dash" do
    msg = create(:sms_message, customer: customer, to: "+8613800138000",
                 template_key: "verify_code", status: "failed",
                 failure_code: "VENDOR_DLR",
                 failure_message: Sms::Message::FAILURE_DELIVERY)
    get "/#{customer.id}/admin/modules/sms/messages/#{msg.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("delivery failed")
    expect(response.body).to include(I18n.t("common.labels.em_dash"))
    expect(response.body).not_to include("sms.failures.delivery_failed")
  end

  it "index does not leak another tenant's messages" do
    create_other_tenant_message

    get "/#{customer.id}/admin/modules/sms/messages"
    expect(response.body).not_to include("+8613800139999")
  end

  it "show does not reveal another tenant's message" do
    leak = create_other_tenant_message

    get "/#{customer.id}/admin/modules/sms/messages/#{leak.id}"
    expect(response).to have_http_status(:not_found)
  end
end
