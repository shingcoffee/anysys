# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS parameter filtering" do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it "redacts the exact top-level SMS handoff and Twilio fields" do
    input = { "to" => "+15559876543", "vars" => { "name" => "private", "code" => "1234" },
              "From" => "+15559876543", "To" => "+15550000000", "Body" => "private text" }
    expect(filter.filter(input).values).to all(eq("[FILTERED]"))
    expect(input["vars"]["name"]).to eq("private")
  end

  it "also redacts nested envelopes without broad substring filtering" do
    filtered = filter.filter("sms" => { "vars" => { "name" => "private" }, "to" => "+15559876543" },
                             "body_html" => "content", "body" => "diagnostic", "total" => 1, "variable_names" => ["name"],
                             "provider" => "twilio", "status" => "queued", "message_id" => 42)
    expect(filtered["sms"]).to eq("vars" => "[FILTERED]", "to" => "[FILTERED]")
    expect(filtered.except("sms")).to include("body_html" => "content", "body" => "diagnostic", "total" => 1,
                                             "variable_names" => ["name"], "provider" => "twilio", "message_id" => 42)
  end

  it "preserves the pre-existing authentication filters" do
    expect(filter.filter("code" => "123456", "access_token" => "secret", "password" => "secret").values)
      .to all(eq("[FILTERED]"))
  end

  it "redacts SMS fields in raw and percent-encoded query-string logging" do
    query = "to=PRIVATE_PHONE&vars[name]=PRIVATE_NAME&vars%5Bcode%5D=PRIVATE_CODE&From=PRIVATE_SENDER&Body=PRIVATE_BODY&total=1&body=diagnostic"
    request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/sms/webhooks/twilio/inbound?#{query}"))
    request.set_header("action_dispatch.parameter_filter", Rails.application.config.filter_parameters)

    expect(request.filtered_path).not_to include("PRIVATE_")
    expect(request.filtered_path).to include("vars[name]=[FILTERED]", "vars%5Bcode%5D=[FILTERED]", "total=1", "body=diagnostic")
  end
end
