# frozen_string_literal: true

require "rails_helper"
require "base64"
require "uri"

RSpec.describe "SMS unsubscribe Rails logging", type: :request do
  let(:customer) { create(:customer) }
  let(:contact) { Sms::Contact.create!(customer: customer, phone_e164: "+8613800138000", consent_status: "granted") }
  let(:token) { Sms::Campaigns::Unsubscribe.token_for(customer: customer, contact: contact, phone_e164: contact.phone_e164) }
  let(:output) { StringIO.new }
  let(:logger) { ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(output, level: Logger::INFO)) }
  let(:payloads) { [] }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
    allow(ActionController::Base).to receive(:logger).and_return(logger)
  end

  def capture_controller_payloads
    capture = lambda do |name, _start, _finish, _id, payload|
      payloads << { event: name, path: payload[:path], params: payload[:params].deep_dup }
    end
    ActiveSupport::Notifications.subscribed(capture, /\A(?:start_processing|process_action)\.action_controller\z/) { yield }
  end

  def expect_safe_logs(capability)
    secrets = [capability, capability.split("--").first, URI.encode_www_form_component(capability),
               contact.phone_e164, URI.encode_www_form_component(contact.phone_e164),
               Base64.strict_encode64(contact.phone_e164), Base64.urlsafe_encode64(contact.phone_e164)]
    expect(output.string).not_to include(*secrets)
    expect(payloads.map(&:inspect).join).not_to include(*secrets)
    expect(payloads).not_to be_empty
    expect(payloads.map { |payload| payload[:path] }).to all(start_with("/sms/unsubscribes/[FILTERED]"))
    expect(payloads.map { |payload| payload[:params].fetch("token") }).to all(eq("[FILTERED]"))
  end

  it "redacts real Started GET/HEAD/POST logs and both controller events while valid browser confirmation still works" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    capability = token
    counts = [Sms::ConsentEvent.count, Sms::OptOut.count, enqueued_jobs.size]
    capture_controller_payloads do
      get sms_unsubscribe_path(capability), params: { locale: "en" }
      expect(response).to have_http_status(:ok)
      expect(request.path_parameters[:token]).to eq(capability)
      form = Nokogiri::HTML(response.body).css("form").find { |element| element["action"].start_with?("/sms/unsubscribes/") }
      csrf = form.at_css('input[name="authenticity_token"]')["value"]
      head sms_unsubscribe_path(capability)
      expect(response).to have_http_status(:ok)
      expect([Sms::ConsentEvent.count, Sms::OptOut.count, enqueued_jobs.size]).to eq(counts)
      post sms_unsubscribe_path(capability), params: { authenticity_token: csrf }
      expect(response).to have_http_status(:ok)
    end
    expect(contact.reload.consent_status).to eq("revoked")
    expect(Sms::ConsentEvent.where(contact_id: contact.id).count).to eq(1)
    expect(output.string).to include('Started GET "/sms/unsubscribes/[FILTERED]?locale=en"',
                                    'Started HEAD "/sms/unsubscribes/[FILTERED]"', 'Started POST "/sms/unsubscribes/[FILTERED]"',
                                    "Processing by Sms::UnsubscribesController#show", "Processing by Sms::UnsubscribesController#create")
    expect(payloads.map { |payload| payload[:event] }).to include("start_processing.action_controller", "process_action.action_controller")
    expect_safe_logs(capability)
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  it "redacts invalid signed paths and keeps ordinary request log paths visible" do
    capability = "invalid-private-capability"
    capture_controller_payloads do
      get sms_unsubscribe_path(capability, format: :json)
      expect(response).to have_http_status(:not_found)
    end
    expect_safe_logs(capability)
    get "/up"
    expect(response).to have_http_status(:ok)
    expect(output.string).to include('Started GET "/up"')
    expect(Sms::ConsentEvent.count).to eq(0)
  end
end
