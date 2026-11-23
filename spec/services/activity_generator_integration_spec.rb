# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ActivityGenerator integration: branch routing execution" do
  let(:elements) do
    [
      { "id" => "s1", "type" => "start", "label" => "Start", "properties" => {} },
      { "id" => "d1", "type" => "decision", "label" => "Check amount",
        "properties" => {
          "routeBy" => "condition",
          "condition" => {
            "type" => "group",
            "joins" => [],
            "conditions" => [
              { "kind" => "field", "leftOperand" => "ctx.amount", "operator" => ">", "rightOperand" => "100" }
            ]
          }
        }
      },
      { "id" => "a1", "type" => "process", "label" => "High value",
        "properties" => {
          "steps" => [{
            "action" => "assign_value",
            "config" => { "resultVar" => "branch_value", "valueType" => "string", "stringValue" => "high" }
          }]
        }
      },
      { "id" => "b1", "type" => "process", "label" => "Low value",
        "properties" => {
          "steps" => [{
            "action" => "assign_value",
            "config" => { "resultVar" => "branch_value", "valueType" => "string", "stringValue" => "low" }
          }]
        }
      },
      { "id" => "e1", "type" => "end", "label" => "End", "properties" => { "responseType" => "none" } }
    ]
  end

  let(:connections) do
    [
      { "id" => "c1", "from" => "s1", "to" => "d1" },
      { "id" => "c2", "from" => "d1", "to" => "a1", "label" => "Yes", "matchValue" => "true" },
      { "id" => "c3", "from" => "d1", "to" => "b1", "label" => "No",  "matchValue" => "false" },
      { "id" => "c4", "from" => "a1", "to" => "e1" },
      { "id" => "c5", "from" => "b1", "to" => "e1" }
    ]
  end

  let(:flowchart) do
    instance_double(
      Flowchart,
      name: "Amount Check",
      elements: elements,
      connections: connections,
      shared?: false,
      customer_owned?: true
    )
  end

  let(:activity_code) { ActivityGenerator.new(flowchart).generate }

  before do
    # Remove any previously defined class from earlier runs to avoid constant collision
    Object.send(:remove_const, :AmountCheckActivity) if Object.const_defined?(:AmountCheckActivity)
  end

  it "generates syntactically valid Ruby code" do
    expect { eval(activity_code) }.not_to raise_error # rubocop:disable Security/Eval
  end

  # Element-level conflict resolution keeps the first topological emitter's
  # ctx key unchanged and renames each subsequent emitter to "result_<sha>".
  # The branches are mutually exclusive at runtime, so exactly one result
  # key (bare or renamed) is populated per run.
  def renamed_result_key(ctx, value)
    ctx.each_pair do |k, v|
      ks = k.to_s
      return k if (ks == "branch_value" || ks.start_with?("branch_value_")) && v == value
    end
    nil
  end

  context "when amount > 100" do
    before { eval(activity_code) } # rubocop:disable Security/Eval

    it "executes the high-value branch and sets the renamed result to 'high'" do
      _signal, (ctx, _) = AmountCheckActivity.call([{ amount: 150 }, {}])
      key = renamed_result_key(ctx, "high")
      expect(key).not_to be_nil
      expect(ctx[key]).to eq("high")
    end

    it "does not populate the low-value branch's renamed key" do
      _signal, (ctx, _) = AmountCheckActivity.call([{ amount: 150 }, {}])
      expect(renamed_result_key(ctx, "low")).to be_nil
    end
  end

  context "when amount <= 100" do
    before { eval(activity_code) } # rubocop:disable Security/Eval

    it "executes the low-value branch and sets the renamed result to 'low'" do
      _signal, (ctx, _) = AmountCheckActivity.call([{ amount: 50 }, {}])
      key = renamed_result_key(ctx, "low")
      expect(key).not_to be_nil
      expect(ctx[key]).to eq("low")
    end

    it "does not populate the high-value branch's renamed key" do
      _signal, (ctx, _) = AmountCheckActivity.call([{ amount: 50 }, {}])
      expect(renamed_result_key(ctx, "high")).to be_nil
    end
  end
end
