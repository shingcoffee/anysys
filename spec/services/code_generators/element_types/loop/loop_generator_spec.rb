# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Loop::LoopGenerator do
  let(:while_condition) { compare_op("ctx.go", "is_true") }
  let(:element) { { "properties" => { "loopType" => "while", "condition" => while_condition } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        state = FlowchartRuntime::Loop.enter(ctx, :_loop) do
          { items: Array(ctx[:items]), index: 0, count: 0 }
        end
        ctx[:_loop_iteration_count] = state[:count]
        while state[:index] < state[:items].size
          if state[:index] >= 100
            return FlowchartRuntime::Loop.fail_limit(ctx, :_loop, max: 100)
          end
          item = state[:items][state[:index]]
          index = state[:index]
          state[:index] += 1
          ctx[:item] = item
          ctx[:index] = index
          state[:count] += 1
          ctx[:_loop_iteration_count] = state[:count]
        end
        FlowchartRuntime::Loop.leave(ctx, :_loop) || :done
      end
    RUBY
  end

  it_behaves_like "covers all configured branches", action_name: "loop",
    base_element: {
      "properties" => {
        "condition" => {
          "type" => "group",
          "joins" => [],
          "conditions" => [
            { "kind" => "field", "leftOperand" => "ctx.go", "operator" => "is_true", "rightOperand" => "" }
          ]
        },
        "collection" => "items",
        "itemVariable" => "item",
        "maxIterations" => 5
      }
    }

  def body(properties, ctx = {})
    described_class.new({ "properties" => properties }, ctx).generate_body
  end

  def errors(properties)
    described_class.new({ "properties" => properties }, context).validate_config(properties)
  end

  def codes(properties)
    errors(properties).map(&:code)
  end

  def compare_op(left, operator, right = "")
    {
      "type" => "group",
      "joins" => [],
      "conditions" => [
        { "kind" => "field", "leftOperand" => left, "operator" => operator, "rightOperand" => right }
      ]
    }
  end

  def compare_lt(left, right)
    compare_op(left, "<", right)
  end

  describe "schema" do
    it "declares the Phase 4 loop fields" do
      names = described_class._config_schema.fields.map(&:name)
      expect(names).to eq(
        %w[loopType runOnceFirst condition collection itemVariable maxIterations stopWhen skipWhen indexVariable collectInto]
      )
    end

    it "has only :required errors for schema defaults" do
      defaults = described_class._config_schema.defaults
      unexpected = errors(defaults).reject { |error| error.code == :required }
      expect(unexpected).to eq([])
    end

    it "accepts sample_input and compiles" do
      sample = described_class.sample_input
      expect(errors(sample)).to eq([])
      expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{body(sample)}\nend") }.not_to raise_error
    end
  end

  describe "#generate_body" do
    it "generates a while loop with the default maxIterations of 100" do
      code = body("loopType" => "while", "condition" => while_condition)
      expect(code).to include("_loop_iteration_count")
      expect(code).to include("state[:count] >= 100")
      expect(code).to include("FlowchartRuntime::Loop.enter")
      expect(code).to include("FlowchartRuntime::Loop.fail_limit")
      expect(code).to include("loop do")
      expect(code).not_to include("100.times")
      expect(code).not_to include(".take(")
      expect(code).not_to include("do_while")
    end

    it "generates a canvas-body while header" do
      expect(generated_step(
        { "loopType" => "while", "maxIterations" => 3, "condition" => compare_lt("ctx.count", "3") },
        context: { loop_has_body: true, done_signal: "Routes::Repeat::Done", loop_state_key: "_repeat" }
      )).to eq(<<~RUBY.chomp)
        def test_step(ctx, **)
          state = FlowchartRuntime::Loop.enter(ctx, :_repeat) { { count: 0 } }
          ctx[:_loop_iteration_count] = state[:count]
          unless FlowchartRuntime::ConditionInput.compare(ctx[:count], "<", 3)
            return FlowchartRuntime::Loop.leave(ctx, :_repeat) || Routes::Repeat::Done
          end
          if state[:count] >= 3
            return FlowchartRuntime::Loop.fail_limit(ctx, :_repeat, max: 3)
          end
          state[:count] += 1
          ctx[:_loop_iteration_count] = state[:count]
          true
        end
      RUBY
    end

    it "emits a straight if/else while header when the canvas has a body" do
      code = described_class.new(
        { "properties" => { "loopType" => "while", "maxIterations" => 3, "condition" => compare_lt("ctx.count", "3") } },
        { loop_has_body: true, done_signal: "Routes::Repeat::Done", loop_state_key: "_repeat" }
      ).generate_body
      expect(code).to include("unless ")
      expect(code).to include("state[:count] >= 3")
      expect(code).to include("FlowchartRuntime::ConditionInput.compare(ctx[:count], \"<\", 3)")
      expect(code).to include("true")
      expect(code).not_to include("loop do")
      expect(code).not_to include("return true")
    end

    it "emits a runOnceFirst header when the canvas has a body" do
      code = described_class.new(
        { "properties" => { "loopType" => "while", "runOnceFirst" => true, "maxIterations" => 5, "condition" => while_condition } },
        { loop_has_body: true }
      ).generate_body
      expect(code).to include("if state[:started]")
      expect(code).not_to include("loop do")
      expect(code).not_to include("return true")
    end

    it "emits ConditionInput.compare for a structured numeric comparison" do
      code = body("loopType" => "while", "condition" => compare_lt("ctx.count", "5"))
      expect(code).to include('FlowchartRuntime::ConditionInput.compare(ctx[:count], "<", 5)')
    end

    it "generates a for_each loop from an input collection path" do
      code = body("loopType" => "for_each", "collection" => "items", "itemVariable" => "item")
      expect(code).to include("state[:items]")
      expect(code).to include("Array(ctx[:items])")
      expect(code).to include("FlowchartRuntime::Loop.enter")
      expect(code).to include("while state[:index] < state[:items].size")
      expect(code).not_to include("each_with_index")
      expect(code).not_to include(".take(")
    end

    it "emits a straight for_each header when the canvas has a body" do
      code = described_class.new(
        { "properties" => { "loopType" => "for_each", "collection" => "items", "itemVariable" => "item" } },
        { loop_has_body: true, done_signal: "Routes::EachItem::Done", loop_state_key: "_each_item" }
      ).generate_body
      expect(code).to include("return ")
      expect(code).to include("if state[:index] >= state[:items].size")
      expect(code).to include("ctx[:item] = item")
      expect(code).not_to include("while state[:index] < state[:items].size")
      expect(code).not_to include("return true")
    end

    it "keeps a real skip while in a canvas-body for_each" do
      skip_when = compare_op("ctx.item", "is_empty")
      code = described_class.new(
        { "properties" => {
          "loopType" => "for_each", "collection" => "items", "itemVariable" => "item",
          "skipWhen" => skip_when
        } },
        { loop_has_body: true }
      ).generate_body
      expect(code).to include("while ")
      expect(code).to include("blank?")
      expect(code).not_to include("next if")
      expect(code).not_to include("return true")
    end

    it "emits custom itemVariable entry as a local" do
      code = body("loopType" => "for_each", "collection" => "items", "itemVariable" => "entry", "indexVariable" => "position")
      expect(code).to include("entry = state[:items]")
      expect(code).to include("ctx[:entry] = entry")
      expect(code).to include("position = state[:index]")
      expect(code).not_to include("item = state[:items]")
    end

    it "wraps the collection expression with Array() for nil safety" do
      code = body("loopType" => "for_each", "collection" => "items", "itemVariable" => "item")
      expect(code).to include("Array(ctx[:items])")
    end

    it "generates runOnceFirst as a post-check while loop" do
      code = body("loopType" => "while", "runOnceFirst" => true, "maxIterations" => 5, "condition" => while_condition)
      expect(code).to include("state[:started]")
      expect(code).to include("state[:count] >= 5")
      expect(code).not_to include("5.times")
    end

    it "injects stopWhen as a successful loop exit" do
      code = body(
        "loopType" => "while",
        "condition" => while_condition,
        "stopWhen" => compare_op("ctx.done", "is_true")
      )
      expect(code).to include("if ")
      expect(code).to include("FlowchartRuntime::Loop.leave")
    end

    it "initializes and pushes to collectInto in a for_each loop" do
      code = body("loopType" => "for_each", "collection" => "items", "itemVariable" => "item", "collectInto" => "results")
      expect(code).to include("ctx[:results] ||= []")
      expect(code).to include("ctx[:results] << item")
    end

    it "emits skipWhen as next in an empty-body for_each loop" do
      code = body(
        "loopType" => "for_each", "collection" => "items", "itemVariable" => "item",
        "skipWhen" => compare_op("ctx.item", "is_empty")
      )
      expect(code).to include("next if ")
    end

    it "does not read removed keys" do
      code = body(
        "loopType" => "while",
        "condition" => while_condition,
        "iterations" => 3,
        "breakCondition" => "ctx[:done]",
        "accumulatorVariable" => "values"
      )
      expect(code).to include("state[:count] >= 100")
      expect(code).not_to include("ctx[:done]")
      expect(code).not_to include("ctx[:values]")
    end
  end

  describe "validation" do
    it "requires condition for while loops" do
      list = errors("loopType" => "while")
      expect(list.map(&:field)).to include("condition")
      expect(list.map(&:code)).to include(:required)
    end

    it "rejects an empty while condition group as an error" do
      list = errors("loopType" => "while", "condition" => { "type" => "group", "joins" => [], "conditions" => [] })
      expect(list.map(&:code)).to include(:empty_condition)
      expect(list.map(&:field)).to include("condition")
    end

    it "requires collection for for_each loops" do
      list = errors("loopType" => "for_each")
      expect(list.map(&:field)).to include("collection")
      expect(list.map(&:code)).to include(:required)
    end

    it "rejects loopType do_while as an undeclared enum value" do
      list = errors("loopType" => "do_while", "condition" => while_condition)
      expect(list.map(&:field)).to include("loopType")
      expect(list.map(&:code)).to include(:not_in_list)
    end

    it "reports leftover keys as unknown_field like other ported elements" do
      list = errors(
        "loopType" => "while",
        "condition" => while_condition,
        "iterations" => 3,
        "breakCondition" => "true",
        "skipCondition" => "true",
        "accumulatorVariable" => "bag"
      )
      %w[iterations breakCondition skipCondition accumulatorVariable].each do |field|
        expect(list).to include(have_attributes(field: field, code: :unknown_field)), field
      end
    end

    it "rejects a collection that still uses a ctx. prefix" do
      list = errors("loopType" => "for_each", "collection" => "ctx.items")
      expect(list.map(&:field)).to include("collection")
      expect(list.map(&:code)).to include(:invalid_identifier)
    end

    it "rejects maxIterations outside 1..10000" do
      expect(codes("loopType" => "while", "condition" => while_condition, "maxIterations" => 0)).to include(:out_of_range)
      expect(codes("loopType" => "while", "condition" => while_condition, "maxIterations" => 10_001)).to include(:out_of_range)
    end

    it "rejects itemVariable and indexVariable names that shadow header locals" do
      %w[state ctx].each do |name|
        properties = { "loopType" => "for_each", "collection" => "items", "itemVariable" => name }
        list = errors(properties)
        expect(list.map(&:field)).to include("itemVariable")
        expect(list.map(&:code)).to include(:reserved_header_local)
        expect(list.join).to include(name)
        expect(errors(properties.merge("itemVariable" => "item", "indexVariable" => name)).map(&:field)).to include("indexVariable")
      end
    end

    it "rejects itemVariable and indexVariable that resolve to the same local" do
      properties = { "loopType" => "for_each", "collection" => "items", "itemVariable" => "entry", "indexVariable" => "entry" }
      list = errors(properties)
      expect(list.map(&:code)).to include(:colliding_loop_variables)
      expect(list.join).to include("itemVariable")
    end

    it "rejects nested condition groups" do
      properties = {
        "loopType" => "while",
        "condition" => { "type" => "group", "conditions" => [{ "type" => "group", "conditions" => [] }] }
      }
      expect(errors(properties).map(&:code)).to include(:nested_group)
    end

    it "rejects a bare comparison that is not a condition group" do
      list = errors("loopType" => "while", "condition" => { "leftOperand" => "ctx.go", "operator" => "is_true" })
      expect(list.map(&:code)).to include(:invalid_condition)
      expect(list.map(&:field)).to include("condition")
    end
  end

  describe "bounded execution" do
    def execute(properties, ctx = {})
      runner = eval("->(ctx) do\n#{body(properties)}\nend") # rubocop:disable Security/Eval
      result = runner.call(ctx)
      [result, ctx]
    end

    it "fails a while loop at maxIterations instead of leaving silently" do
      result, ctx = execute(
        { "loopType" => "while", "condition" => while_condition, "maxIterations" => 3 },
        go: true
      )
      expect(result).to be(false)
      expect(ctx[:_loop_iteration_count]).to eq(3)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.loop_limit", max: 3)])
    end

    it "fails a runOnceFirst while loop at maxIterations" do
      result, ctx = execute(
        { "loopType" => "while", "runOnceFirst" => true, "condition" => while_condition, "maxIterations" => 2 },
        go: true
      )
      expect(result).to be(false)
      expect(ctx[:_loop_iteration_count]).to eq(2)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.loop_limit", max: 2)])
    end

    it "fails a for_each loop when items remain after maxIterations" do
      result, ctx = execute(
        { "loopType" => "for_each", "collection" => "items", "maxIterations" => 2 },
        items: [10, 20, 30]
      )
      expect(result).to be(false)
      expect(ctx[:_loop_iteration_count]).to eq(2)
      expect(ctx[:item]).to eq(20)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.loop_limit", max: 2)])
    end

    it "leaves successfully when a for_each collection is exhausted within the limit" do
      result, ctx = execute(
        { "loopType" => "for_each", "collection" => "items", "maxIterations" => 10 },
        items: [10, 20, 30]
      )
      expect(result).to eq(:done)
      expect(ctx[:_loop_iteration_count]).to eq(3)
      expect(ctx[:errors]).to be_nil
    end

    it "leaves successfully when the while condition becomes false" do
      result, ctx = execute(
        { "loopType" => "while", "condition" => compare_lt("ctx._loop_iteration_count", "2"), "maxIterations" => 10 }
      )
      expect(result).to eq(:done)
      expect(ctx[:_loop_iteration_count]).to eq(2)
      expect(ctx[:errors]).to be_nil
    end

    it "stops early on stopWhen without failing" do
      result, ctx = execute(
        {
          "loopType" => "while",
          "condition" => while_condition,
          "maxIterations" => 10,
          "stopWhen" => compare_op("ctx._loop_iteration_count", ">=", "0")
        },
        go: true
      )
      expect(result).to eq(:done)
      expect(ctx[:_loop_iteration_count]).to eq(0)
      expect(ctx[:errors]).to be_nil
    end

    it "skips for_each items matching skipWhen and collects the rest" do
      result, ctx = execute(
        {
          "loopType" => "for_each",
          "collection" => "items",
          "skipWhen" => compare_op("ctx.item", "is_empty"),
          "collectInto" => "values"
        },
        items: [nil, 2, nil, 4]
      )
      expect(result).to eq(:done)
      expect(ctx[:values]).to eq([2, 4])
      expect(ctx[:_loop_iteration_count]).to eq(2)
    end

    it "counts skipped for_each items toward maxIterations" do
      result, ctx = execute(
        {
          "loopType" => "for_each",
          "collection" => "items",
          "maxIterations" => 2,
          "skipWhen" => compare_op("ctx.item", "is_empty")
        },
        items: [nil, nil, 3]
      )
      expect(result).to be(false)
      expect(ctx[:_loop_iteration_count]).to eq(0)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.loop_limit", max: 2)])
    end
  end

  describe "limit error locales" do
    it "translates flowchart_runtime.errors.loop_limit in en and zh-CN" do
      config = { "loopType" => "for_each", "collection" => "items", "maxIterations" => 1 }
      {
        en: I18n.t("flowchart_runtime.errors.loop_limit", max: 1, locale: :en),
        "zh-CN": I18n.t("flowchart_runtime.errors.loop_limit", max: 1, locale: :"zh-CN")
      }.each do |locale, expected|
        I18n.with_locale(locale) do
          result = CodeGenerators::TestRunner.execute(described_class, config: config, ctx: { items: [1, 2] })
          expect(result[:outcome]).to be(false)
          expect(result[:ctx][:errors]).to eq([expected])
        end
      end
    end
  end

  describe "localized validation" do
    [
      [{ "loopType" => "for_each" }, "collection is required", "必须填写 collection"],
      [{ "loopType" => "while" }, "condition is required", "必须填写 condition"],
      [{ "loopType" => "for_each", "collection" => "items", "itemVariable" => "state" },
        "itemVariable cannot be state because that name is reserved for the loop header",
        "itemVariable 不能使用 state，该名称已保留给循环头"],
      [{ "loopType" => "for_each", "collection" => "items", "indexVariable" => "ctx" },
        "indexVariable cannot be ctx because that name is reserved for the loop header",
        "indexVariable 不能使用 ctx，该名称已保留给循环头"],
      [{ "loopType" => "for_each", "collection" => "items", "itemVariable" => "entry", "indexVariable" => "entry" },
        "itemVariable and indexVariable must be different",
        "itemVariable 与 indexVariable 不能相同"]
    ].each do |properties, english, chinese|
      it "translates validation errors at call time for #{properties['loopType']}" do
        generator = described_class.new({ "properties" => properties }, {})
        { en: english, "zh-CN": chinese }.each do |locale, expected|
          I18n.with_locale(locale) do
            expect(generator.validate_config(properties).map(&:to_s)).to eq([expected])
          end
        end
      end
    end
  end

  describe "locale files" do
    it "keeps identical flowchart_elements.loop key sets and %{ } variables" do
      english = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_elements_loop.en.yml")).fetch("en")
      chinese = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_elements_loop.zh-CN.yml")).fetch("zh-CN")

      flatten = lambda do |hash, prefix = nil|
        hash.each_with_object([]) do |(key, value), keys|
          path = prefix ? "#{prefix}.#{key}" : key.to_s
          if value.is_a?(Hash)
            keys.concat(flatten.call(value, path))
          else
            keys << path
          end
        end
      end

      expect(flatten.call(chinese).sort).to eq(flatten.call(english).sort)
      english.fetch("flowchart_elements").fetch("loop").fetch("errors").each do |key, value|
        zh = chinese.fetch("flowchart_elements").fetch("loop").fetch("errors").fetch(key)
        expect(value.scan(/%\{(\w+)\}/).flatten).to eq(zh.scan(/%\{(\w+)\}/).flatten)
      end
    end
  end
end
