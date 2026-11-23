# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS public unsubscribe HTTP", type: :request do
  let(:customer) { create(:customer) }
  let(:contact) { Sms::Contact.create!(customer: customer, phone_e164: "+8613800138000", country_code: "CN", consent_status: "granted") }
  let(:token) { Sms::Campaigns::Unsubscribe.token_for(customer: customer, contact: contact, phone_e164: contact.phone_e164) }
  let(:path) { sms_unsubscribe_path(token, format: :json) }

  it "keeps GET/HEAD read-only and returns only a masked read model, ignoring unsigned tenant hints" do
    token
    counts = [Sms::ConsentEvent.count, Sms::OptOut.count, Sms::Message.count, enqueued_jobs.size]
    get path, params: { customer_id: create(:customer).id, contact_id: -1, phone: "+8613800139999" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("data").keys).to match_array(%w[masked_phone already_unsubscribed])
    expect(response.body).not_to include(contact.phone_e164)
    head path
    expect(response).to have_http_status(:ok)
    expect(contact.reload.consent_status).to eq("granted")
    expect([Sms::ConsentEvent.count, Sms::OptOut.count, Sms::Message.count, enqueued_jobs.size]).to eq(counts)
  end

  it "uses only the signed original phone and tenant and makes POST replay idempotent" do
    original = contact.phone_e164
    token
    contact.update!(phone_e164: "+8613800138001", consent_status: "granted")
    2.times do
      post path, params: { customer_id: create(:customer).id, phone: contact.phone_e164 }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "already_unsubscribed")).to be(true)
    end
    expect(contact.reload.consent_status).to eq("granted")
    expect(Sms::ConsentEvent.where(customer_id: customer.id, contact_id: contact.id).count).to eq(1)
    expect(Sms::OptOut.where(customer_id: customer.id).pluck(:phone_e164)).to eq([original])
  end

  it "rejects invalid, wrong-purpose and expired tokens without writes" do
    invalid = ["invalid", Rails.application.message_verifier(Sms::Campaigns::Unsubscribe::PURPOSE).generate({}, purpose: "other")]
    invalid.each do |value|
      get sms_unsubscribe_path(value, format: :json), params: { locale: "zh-CN" }
      expect(response).to have_http_status(:not_found)
      post sms_unsubscribe_path(value, format: :json), as: :json
      expect(response).to have_http_status(:not_found)
    end
    token
    travel 366.days do
      get path
      expect(response).to have_http_status(:not_found)
    end
    expect(Sms::ConsentEvent.count).to eq(0)
    expect(Sms::OptOut.count).to eq(0)
  end

  it "retains browser CSRF protection instead of accepting a token-only cross-site POST" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post sms_unsubscribe_path(token)
    expect(response).to have_http_status(:unprocessable_entity), response.body
    expect(response.body).to include("InvalidAuthenticityToken")
    expect(Sms::ConsentEvent.count).to eq(0)
    expect(contact.reload.consent_status).to eq("granted")
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  it "confirms through the public browser form with a valid session-bound CSRF token" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get sms_unsubscribe_path(token)
    expect(response).to have_http_status(:ok)
    form = Nokogiri::HTML(response.body).css("form").find { |element| element["action"].start_with?("/sms/unsubscribes/") }
    csrf = form.at_css('input[name="authenticity_token"]')["value"]
    expect(contact.reload.consent_status).to eq("granted")
    post sms_unsubscribe_path(token), params: { authenticity_token: csrf }
    expect(response).to have_http_status(:ok)
    expect(contact.reload.consent_status).to eq("revoked")
    expect(Sms::ConsentEvent.count).to eq(1)
    expect(response.body).not_to include(contact.phone_e164)
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
