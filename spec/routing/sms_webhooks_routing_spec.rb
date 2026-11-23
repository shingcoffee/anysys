# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sms::Webhooks routing", type: :routing do
  it "routes a registered provider (twilio) to Sms::WebhooksController#create" do
    expect(post: "/sms/webhooks/twilio/delivery").to route_to(
      controller: "sms/webhooks", action: "create", provider: "twilio", kind: "delivery"
    )
  end

  it "routes the inbound kind too" do
    expect(post: "/sms/webhooks/twilio/inbound").to route_to(
      controller: "sms/webhooks", action: "create", provider: "twilio", kind: "inbound"
    )
  end

  it "does not route an unregistered provider — no adapter file, no route match" do
    expect(post: "/sms/webhooks/unregistered_vendor/delivery").not_to be_routable
  end
end
