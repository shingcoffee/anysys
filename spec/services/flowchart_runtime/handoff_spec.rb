# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Handoff do
  let_it_be(:customer) { create(:customer) }

  def enable_demo!
    enable_module!("demo_handoff", customer, name: "Demo").tap { |fm| fm.update!(handoff_enabled: true) }
  end

  describe "ACTIONS" do
    it "names the steps that end a submission in a module" do
      expect(described_class::ACTIONS).to contain_exactly("hand_off_to_module", "request_payment")
    end
  end

  describe ".request" do
    it "writes the handoff onto the submission outcome" do
      enable_demo!
      ctx = { customer_id: customer.id, errors: [], submission_outcome: { "preset" => "thank_you" } }

      expect(described_class.request(ctx, module_key: "demo_handoff", input: { amount: 12.5 })).to be(true)
      expect(ctx[:submission_outcome]).to eq(
        "preset" => "thank_you",
        "handoff" => { "module_key" => "demo_handoff", "input" => { "amount" => 12.5 } }
      )
    end

    it "parks an exit_target when one is supplied" do
      enable_demo!
      ctx = { customer_id: customer.id, errors: [] }

      described_class.request(
        ctx,
        module_key: "demo_handoff",
        input: { amount: 1 },
        exit_target: { kind: "url", url: "https://ok.test" }
      )
      expect(ctx[:submission_outcome]["handoff"]["exit_target"]).to eq(
        "kind" => "url", "url" => "https://ok.test"
      )
    end

    it "fails when the module is not handoff-enabled for the customer" do
      ctx = { customer_id: customer.id, errors: [] }

      expect(described_class.request(ctx, module_key: "demo_handoff", input: { amount: 1 })).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.hand_off_to_module.module_unavailable")])
      expect(ctx[:submission_outcome]).to be_nil
    end
  end
end
