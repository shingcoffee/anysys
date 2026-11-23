# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Subsystems::Screen do
  let(:screen) { described_class.new(allowed_text: "Post to https://hooks.school.test/new. Mail registrar@school.test please.") }

  def normalized(*steps)
    processes = steps.each_with_index.map do |step, index|
      { "id" => "p#{index}", "type" => "process", "label" => step["action"], "steps" => [step] }
    end
    FlowchartDefinitions::Normalizer.call(
      "name" => "Notify",
      "elements" => [{ "id" => "start_1", "type" => "start" }, *processes, { "id" => "end_1", "type" => "end" }],
      "connections" => []
    )
  end

  it "accepts addresses the admin wrote" do
    document = normalized(
      { "action" => "send_webhook", "config" => { "url" => "'https://hooks.school.test/new'", "payloadExpression" => "ctx[:model]" } },
      { "action" => "send_email", "config" => { "to" => "registrar@school.test", "subject" => "New student" } }
    )

    expect(screen.unknown_values(document)).to eq([])
    expect(screen.errors(document)).to eq([])
  end

  it "accepts an address that is the action's palette default" do
    default_url = "https://api.vendor.test/v1"
    allow(FlowchartDefinitions::Palette).to receive(:action).and_call_original
    allow(FlowchartDefinitions::Palette).to receive(:action).with("api_call")
      .and_return({ "config_fields" => [{ "name" => "url", "default" => default_url }] })

    document = normalized({ "action" => "api_call", "config" => { "url" => default_url } })

    expect(screen.unknown_values(document)).to eq([])
  end

  it "reports a web or email address the admin never wrote" do
    document = normalized(
      { "action" => "send_webhook", "config" => { "url" => "https://evil.test/hook" } },
      { "action" => "send_email", "config" => { "to" => "someone@else.test" } }
    )

    expect(screen.unknown_values(document)).to eq(["https://evil.test/hook", "someone@else.test"])
    expect(screen.errors(document)).to eq([
      I18n.t("ai_assistant.subsystems.screen.unknown_value", value: "https://evil.test/hook"),
      I18n.t("ai_assistant.subsystems.screen.unknown_value", value: "someone@else.test")
    ])
  end

  it "refuses secret values and credential headers" do
    document = normalized(
      { "action" => "api_call", "config" => { "url" => "https://hooks.school.test/new", "authToken" => "abc123",
                                              "headers" => [{ "key" => "Authorization", "value" => "Bearer xyz" }, { "key" => "Accept", "value" => "json" }] } },
      { "action" => "send_webhook", "config" => { "url" => "https://hooks.school.test/new", "secretExpression" => "" } }
    )

    expect(screen.errors(document)).to eq([
      I18n.t("ai_assistant.subsystems.screen.secret_value", step: "api_call", field: "authToken"),
      I18n.t("ai_assistant.subsystems.screen.secret_value", step: "api_call", field: "Authorization")
    ])
  end

  it "refuses overwriting a field the page fills before processing runs" do
    screen = described_class.new(allowed_text: "", filled: ["customer_ref"])
    document = normalized(
      { "action" => "update_model", "config" => { "modelVariable" => "model",
                                                  "assignments" => [{ "key" => "status", "value" => "'Placed'" },
                                                                    { "key" => "customer_ref", "value" => "ctx[:x]" }] } },
      { "action" => "set_record_fields", "config" => { "assignments" => [{ "key" => "customer_ref", "value" => "ctx[:y]" }] } },
      { "action" => "update_model", "config" => { "modelVariable" => "product",
                                                  "assignments" => [{ "key" => "customer_ref", "value" => "ctx[:z]" }] } }
    )

    expect(screen.errors(document)).to eq([I18n.t("ai_assistant.subsystems.screen.filled_field", field: "customer_ref")])
  end

  it "refuses method calls on the signed-in user snapshot" do
    document = normalized(
      { "action" => "load_current_user", "config" => { "resultVar" => "shopper" } },
      { "action" => "update_model", "config" => { "assignments" => [
        { "key" => "placed_by", "value" => "ctx[:shopper].id" },
        { "key" => "contact", "value" => "ctx[:shopper]&.email" },
        { "key" => "person", "value" => "ctx[:shopper].dig(\"person_entries\", \"7\")" },
        { "key" => "name", "value" => "ctx[:shopper][\"name\"]" },
        { "key" => "other", "value" => "ctx[:current_user].id" }
      ] } }
    )

    expect(screen.errors(document)).to eq([
      I18n.t("ai_assistant.subsystems.screen.user_hash", variable: "shopper", key: "id"),
      I18n.t("ai_assistant.subsystems.screen.user_hash", variable: "shopper", key: "email")
    ])
  end

  it "builds the allowed text from the admin's own messages only" do
    customer = create(:customer)
    conversation = create(:ai_assistant_conversation, customer: customer, user: create(:user, :admin, customer: customer))
    create(:ai_assistant_message, conversation: conversation, customer: customer, role: "user", body: "Use https://a.test/x")
    create(:ai_assistant_message, conversation: conversation, customer: customer, role: "assistant", body: "Or https://b.test/y?")
    document = normalized(
      { "action" => "send_webhook", "config" => { "url" => "https://a.test/x" } },
      { "action" => "send_webhook", "config" => { "url" => "https://b.test/y" } }
    )

    expect(described_class.for(conversation).unknown_values(document)).to eq(["https://b.test/y"])
  end
end
