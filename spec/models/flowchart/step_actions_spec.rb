# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowchart::StepActions do
  let(:customer) { create(:customer) }

  def flowchart_with_steps(*actions)
    steps = actions.map do |item|
      action, config = item.is_a?(Array) ? item : [item, {}]
      { "action" => action, "config" => config }
    end
    create(:flowchart, customer: customer, configuration: {
      "elements" => [
        { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
        { "id" => "p", "type" => "process", "label" => "Work", "properties" => { "steps" => steps } },
        { "id" => "e", "type" => "end", "label" => "End", "properties" => {} }
      ],
      "connections" => [
        { "id" => "c1", "from" => "s", "to" => "p" },
        { "id" => "c2", "from" => "p", "to" => "e" }
      ],
      "metadata" => {}
    }.to_json)
  end

  describe "#step_actions" do
    it "lists unique process step actions from the canvas" do
      flowchart = flowchart_with_steps("build_contract", "validate_contract", "build_contract", "save_model")

      expect(flowchart.step_actions).to eq(%w[build_contract validate_contract save_model])
    end

    it "ignores blank and non-hash steps" do
      flowchart = create(:flowchart, customer: customer, configuration: {
        "elements" => [
          { "id" => "s", "type" => "start", "properties" => {} },
          { "id" => "p", "type" => "process", "properties" => {
            "steps" => [{ "action" => "save_model" }, { "action" => "" }, "nope", { "action" => nil }]
          } },
          { "id" => "e", "type" => "end", "properties" => {} }
        ],
        "connections" => [{ "from" => "s", "to" => "p" }, { "from" => "p", "to" => "e" }],
        "metadata" => {}
      }.to_json)

      expect(flowchart.step_actions).to eq(["save_model"])
    end
  end

  describe "#hands_off?" do
    it "is false when no step hands the visitor to a module" do
      expect(flowchart_with_steps("build_contract", "save_model")).not_to be_hands_off
    end

    it "is true for a hand_off_to_module step" do
      expect(flowchart_with_steps(["hand_off_to_module", { "moduleKey" => "payment" }])).to be_hands_off
    end

    it "is true for a request_payment step" do
      expect(flowchart_with_steps(["request_payment", {
        "amount" => "10.00", "currency" => "CNY", "subject" => '"Fee"'
      }])).to be_hands_off
    end
  end
end
