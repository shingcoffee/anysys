# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Decision::DecisionGenerator do
  def field_row(left, operator, right = "")
    { "kind" => "field", "leftOperand" => left, "operator" => operator, "rightOperand" => right }
  end

  def group(*rows, joins: [])
    { "type" => "group", "joins" => joins, "conditions" => rows }
  end

  def value_props(subject = "ctx[:status]")
    { "routeBy" => "value", "subject" => subject }
  end

  def condition_props(condition)
    { "routeBy" => "condition", "condition" => condition }
  end

  def messages(errors)
    errors.map { |error| error.respond_to?(:message) ? error.message : error.to_s }
  end

  let(:yes_no_topology) do
    {
      flowchart_topology: {
        outgoing_branches: [
          { "signal" => "Routes::Decision::Yes", "semantic" => "yes", "matchValue" => "true" },
          { "signal" => "Routes::Decision::No", "semantic" => "no", "matchValue" => "false" }
        ]
      }
    }
  end
  let(:value_topology) do
    {
      flowchart_topology: {
        outgoing_branches: [
          { "signal" => "Routes::Decision::Active", "semantic" => "active", "matchValue" => "active" },
          { "signal" => "Routes::Decision::Otherwise", "semantic" => "otherwise", "matchValue" => "" }
        ]
      }
    }
  end
  let(:element) { { "label" => "Decision", "properties" => condition_props(group(field_row("ctx.status", "==", "active"))) } }
  let(:context) { yes_no_topology }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:status] == "active"
      end
    RUBY
  end

  it "generates a yes/no switch from topology" do
    expect(generated_step(described_class.sample_input, context: yes_no_topology)).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        if ctx[:status] == "active"
          Routes::Decision::Yes
        else
          Routes::Decision::No
        end
      end
    RUBY
  end

  it "generates a value switch from topology" do
    expect(generated_step(value_props, context: value_topology)).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        case ctx[:status].to_s
        when "active" then Routes::Decision::Active
        else Routes::Decision::Otherwise
        end
      end
    RUBY
  end

  it "evaluates the sample condition" do
    result = CodeGenerators::TestRunner.execute(described_class, config: described_class.sample_input, ctx: { status: "active" })
    expect(result[:outcome]).to eq(true)
    result = CodeGenerators::TestRunner.execute(described_class, config: described_class.sample_input, ctx: { status: "draft" })
    expect(result[:outcome]).to eq(false)
  end

  def generator(properties, generator_context = context)
    described_class.new({ "label" => "Decision", "properties" => properties }, generator_context)
  end

  it "declares the ported routeBy / subject / condition schema" do
    fields = described_class.config_fields
    expect(fields.map { |field| field[:name] }).to eq(%w[routeBy subject condition])
    expect(fields.map { |field| field[:role] }).to eq(%i[enum expression conditions])
    route_by = fields.find { |field| field[:name] == "routeBy" }
    expect(route_by[:options][:values]).to eq(%w[value condition])
    expect(route_by[:options][:default]).to eq("condition")
    expect(fields.find { |field| field[:name] == "subject" }[:options][:visible]).to eq("routeBy" => "value")
    expect(fields.find { |field| field[:name] == "condition" }[:options][:visible]).to eq("routeBy" => "condition")
  end

  it "exposes English and zh-CN field option labels" do
    expect(I18n.t("flowchart_elements.decision.fields.routeBy.options.value", locale: :en)).to eq("Value")
    expect(I18n.t("flowchart_elements.decision.fields.routeBy.options.condition", locale: :en)).to eq("Yes / No")
    expect(I18n.t("flowchart_elements.decision.fields.routeBy.options.value", locale: :"zh-CN")).to eq("按取值")
    expect(I18n.t("flowchart_elements.decision.fields.routeBy.options.condition", locale: :"zh-CN")).to eq("按是/否")
  end

  it "routes value mode from topology-managed connection match values" do
    code = generator(value_props, value_topology).generate_body

    expect(code).to include("case ctx[:status].to_s")
    expect(code).to include('when "active" then Routes::Decision::Active')
    expect(code).to include("else Routes::Decision::Otherwise")
    expect(code).not_to include("ctx[:_route_")
    expect(code).not_to include("client_branch")
    expect { RubyVM::InstructionSequence.compile(generator(value_props, value_topology).generate_step_method) }
      .not_to raise_error
  end

  it "returns the subject value without topology" do
    code = described_class.new(
      { "label" => "Decision", "properties" => value_props },
      {}
    ).generate_body
    expect(code).to include(".to_s")
    expect(code).not_to include("Routes::")
  end

  it "returns the boolean condition without topology" do
    numeric = group(field_row("ctx.params.amount", ">", "100"))
    code = described_class.new({ "label" => "Decision", "properties" => condition_props(numeric) }, {}).generate_body
    expect(code).to include('FlowchartRuntime::ConditionInput.compare(FlowchartRuntime::Step.dig(ctx[:params], :amount), ">", 100)')
    expect(code).not_to include("Routes::")
  end

  it "quotes adversarial match values" do
    adversarial_context = {
      flowchart_topology: {
        outgoing_branches: [
          { "signal" => "Routes::Decision::Bad", "semantic" => "bad", "matchValue" => %("\nKernel.raise("MATCH_INJECTION")) },
          { "signal" => "Routes::Decision::Otherwise", "semantic" => "otherwise", "matchValue" => "" }
        ]
      }
    }
    code = generator(value_props, adversarial_context).generate_step_method

    expect { RubyVM::InstructionSequence.compile(code) }.not_to raise_error
    expect(code).not_to match(/^Kernel\.raise/)
  end

  it "rejects leftover defaultBranchIndex and properties.branches keys" do
    props = value_props.merge(
      "defaultBranchIndex" => 0,
      "branches" => [{ "matchValue" => "ignored", "branchKey" => "legacy" }]
    )
    errors = generator(props, value_topology).validate_config(props)
    expect(messages(errors)).to include(
      a_string_matching(/defaultBranchIndex is not a recognized setting/),
      a_string_matching(/branches is not a recognized setting/)
    )
    expect { generator(props, value_topology).generate_body }
      .to raise_error(ArgumentError, /not a recognized setting/)
  end

  it "requires at least two topology-provided outgoing branches" do
    one_branch = { flowchart_topology: { outgoing_branches: [{ "signal" => "Routes::Decision::Yes", "semantic" => "yes", "matchValue" => "true" }] } }
    props = condition_props(group(field_row("ctx.status", "is_true")))
    one_branch_generator = described_class.new({ "label" => "Decision", "properties" => props }, one_branch)
    errors = one_branch_generator.validate_config(props)

    expect(errors).to include(have_attributes(field: "branches", code: :too_few_branches))
    expect(messages(errors)).to include("Decision requires at least two outgoing connections")
    expect { one_branch_generator.generate_body }
      .to raise_error(ArgumentError, /Decision requires at least two outgoing connections/)
  end

  it "rejects duplicate match values after stripping" do
    topology = {
      flowchart_topology: {
        outgoing_branches: [
          { "signal" => "Routes::Decision::A", "semantic" => "a", "matchValue" => " active " },
          { "signal" => "Routes::Decision::B", "semantic" => "b", "matchValue" => "active" }
        ]
      }
    }
    props = value_props
    errors = generator(props, topology).validate_config(props)
    expect(errors).to include(have_attributes(field: "branches", code: :duplicate_match_value))
    expect(messages(errors)).to include("Match values must be unique")
  end

  it "rejects a second Otherwise branch" do
    topology = {
      flowchart_topology: {
        outgoing_branches: [
          { "signal" => "Routes::Decision::A", "semantic" => "a", "matchValue" => " " },
          { "signal" => "Routes::Decision::B", "semantic" => "b", "matchValue" => "" }
        ]
      }
    }
    props = value_props
    errors = generator(props, topology).validate_config(props)
    expect(errors).to include(have_attributes(field: "branches", code: :multiple_otherwise))
  end

  it "requires Yes plus No or Otherwise in condition mode" do
    no_yes = {
      flowchart_topology: {
        outgoing_branches: [
          { "signal" => "Routes::Decision::No", "semantic" => "no", "matchValue" => "false" },
          { "signal" => "Routes::Decision::Otherwise", "semantic" => "otherwise", "matchValue" => "" }
        ]
      }
    }
    props = condition_props(group(field_row("ctx.ok", "is_true")))
    errors = generator(props, no_yes).validate_config(props)
    expect(errors).to include(have_attributes(field: "branches", code: :missing_yes_branch))
  end

  it "rejects non-boolean match values in condition mode" do
    mixed = {
      flowchart_topology: {
        outgoing_branches: [
          { "signal" => "Routes::Decision::Yes", "semantic" => "yes", "matchValue" => "true" },
          { "signal" => "Routes::Decision::High", "semantic" => "high", "matchValue" => "high" }
        ]
      }
    }
    props = condition_props(group(field_row("ctx.ok", "is_true")))
    errors = generator(props, mixed).validate_config(props)
    expect(errors).to include(have_attributes(field: "branches", code: :invalid_condition_match))
  end

  it "accepts Yes plus Otherwise in condition mode" do
    topology = {
      flowchart_topology: {
        outgoing_branches: [
          { "signal" => "Routes::Decision::Yes", "semantic" => "yes", "matchValue" => "true" },
          { "signal" => "Routes::Decision::Otherwise", "semantic" => "otherwise", "matchValue" => "" }
        ]
      }
    }
    props = condition_props(group(field_row("ctx.ok", "is_true")))
    expect(messages(generator(props, topology).validate_config(props))).to be_empty
    expect(generator(props, topology).generate_body).to include("Routes::Decision::Otherwise")
  end

  it "rejects empty groups and empty field rows" do
    empty_group = group
    empty_row = group(field_row("", "", ""))

    expect(generator(condition_props(empty_group)).validate_config(condition_props(empty_group)))
      .to include(have_attributes(field: "condition", code: :empty_condition))
    expect(generator(condition_props(empty_row)).validate_config(condition_props(empty_row)))
      .to include(have_attributes(field: "condition", code: :missing_left))
    expect { generator(condition_props(empty_group)).generate_body }
      .to raise_error(ArgumentError, /Add at least one condition/)
  end

  it "rejects missing operators, unknown operators, and missing binary operands" do
    missing_right = group(field_row("ctx.status", "==", ""))
    missing_op = group(field_row("ctx.status", "", ""))
    unknown = group(field_row("ctx.status", "bogus", "x"))
    unary = group(field_row("ctx.status", "is_empty"))

    expect(generator(condition_props(missing_right)).validate_config(condition_props(missing_right)))
      .to include(have_attributes(field: "condition", code: :missing_right))
    expect(generator(condition_props(missing_op)).validate_config(condition_props(missing_op)))
      .to include(have_attributes(field: "condition", code: :missing_operator))
    expect(generator(condition_props(unknown)).validate_config(condition_props(unknown)))
      .to include(have_attributes(field: "condition", code: :unknown_operator))
    expect(messages(generator(condition_props(unary)).validate_config(condition_props(unary)))).to be_empty
  end

  it "rejects nested condition groups" do
    nested = group(
      {
        "type" => "group",
        "joins" => [],
        "conditions" => [field_row("ctx.code", "matches_regex", "\\A[A-Z]+\\z")]
      }
    )
    props = condition_props(nested)
    errors = generator(props).validate_config(props)
    expect(errors).to include(have_attributes(field: "condition", code: :nested_group))
    expect(messages(errors)).to include("Condition row 1 cannot be a nested group")
    expect { generator(props).generate_body }
      .to raise_error(ArgumentError, /Condition row 1 cannot be a nested group/)
  end

  it "rejects a malformed matches_regex pattern on a flat row" do
    bad_regex = group(field_row("ctx.code", "matches_regex", "["))
    props = condition_props(bad_regex)
    expect(generator(props).validate_config(props))
      .to include(have_attributes(field: "condition", code: :invalid_regex))
    expect { generator(props).generate_body }
      .to raise_error(ArgumentError, /Condition row 1 has an invalid pattern/)
  end

  it "emits ConditionInput.compare for a numeric comparison condition" do
    numeric = group(field_row("ctx.params.amount", ">", "100"))
    code = generator(condition_props(numeric), yes_no_topology).generate_body

    expect(code).to include('FlowchartRuntime::ConditionInput.compare(FlowchartRuntime::Step.dig(ctx[:params], :amount), ">", 100)')
    expect(code).to include("Routes::Decision::Yes")
    expect(code).to include("Routes::Decision::No")
  end

  it "accepts a valid flat matches_regex pattern" do
    props = condition_props(group(field_row("ctx.code", "matches_regex", "\\A[A-Z]+\\z")))
    expect(messages(generator(props).validate_config(props))).to be_empty
  end

  it "returns translated zh-CN messages for nested groups and unknown operators" do
    nested = group({ "type" => "group", "joins" => [], "conditions" => [field_row("ctx.a", "==", "1")] })
    unknown = group(field_row("ctx.a", "wat", "1"))

    I18n.with_locale(:"zh-CN") do
      expect(messages(generator(condition_props(nested)).validate_config(condition_props(nested))))
        .to include("第 1 行条件不能是嵌套条件组")
      expect(messages(generator(condition_props(unknown)).validate_config(condition_props(unknown))))
        .to include("第 1 行条件的运算符无效")
    end
  end
end
