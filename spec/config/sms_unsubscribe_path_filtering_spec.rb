# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS unsubscribe path filtering" do
  def request_for(path, script_name: "")
    request = ActionDispatch::Request.new(Rack::MockRequest.env_for(path, "SCRIPT_NAME" => script_name))
    request.set_header("action_dispatch.parameter_filter", Rails.application.config.filter_parameters)
    request
  end

  it "redacts the capability before routing while preserving Rails query filtering and the real URL" do
    path = "/sms/unsubscribes/private-capability.json?locale=zh-CN&token=query-secret&to=PRIVATE_PHONE"
    request = request_for(path)
    expect(request.path_parameters).to eq({})
    expect(request.filtered_path).to eq("/sms/unsubscribes/[FILTERED]?locale=zh-CN&token=[FILTERED]&to=[FILTERED]")
    expect(request.filtered_path).not_to include("private-capability", "query-secret", "PRIVATE_PHONE")
    expect(request.fullpath).to eq(path)
    expect(request.path_info).to eq("/sms/unsubscribes/private-capability.json")
  end

  it "covers mounted and router-normalized paths without changing SCRIPT_NAME or PATH_INFO" do
    ["/sms/unsubscribes/private-capability", "/sms//unsubscribes/private-capability/", "/sms/unsubscribes/private%2Dcapability"].each do |path|
      request = request_for(path, script_name: "/proxy")
      expect(request.filtered_path).to eq("/proxy/sms/unsubscribes/[FILTERED]")
      expect(request.path_info).to eq(path)
      expect(request.script_name).to eq("/proxy")
    end
  end

  it "keeps neighboring SMS, Email and payment log paths unchanged" do
    %w[/sms/webhooks/twilio/inbound /sms/unsubscribes_extra/private-capability
       /sms/unsubscribes/private-capability/extra /unsubscribe/email-capability
       /12345678/payments/checkouts/payment-reference /12345678/admin/modules/sms/segments].each do |path|
      expect(request_for(path).filtered_path).to eq(path)
    end
  end

  it "keeps a cached log path redacted after the router normalizes the shared request environment" do
    request = request_for("/sms//unsubscribes/private-capability/?locale=en&token=query-secret")
    expected = "/sms/unsubscribes/[FILTERED]?locale=en&token=[FILTERED]"
    expect(request.filtered_path).to eq(expected)
    request.path_info = ActionDispatch::Journey::Router::Utils.normalize_path(request.path_info)
    expect(request.filtered_path).to eq(expected)
    expect(request.path_parameters).to eq({})
  end
end
