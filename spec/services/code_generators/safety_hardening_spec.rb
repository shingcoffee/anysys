# frozen_string_literal: true

require "rails_helper"
# MetadataDSL is defined in app/services/code_generators/metadata_dsl.rb but
# its camelization (Rails default: MetadataDsl) doesn't match the actual
# constant name. The production code path loads it via `require_relative`
# from GeneratorInterface, which sidesteps Zeitwerk. Touch GeneratorInterface
# here so MetadataDSL is defined before any describe block references it.
CodeGenerators::GeneratorInterface

# Per-component hardening coverage for the code-generation pipeline.
# These specs lock down the small but high-leverage safety invariants
# spread across base_generator, shared helpers, emission_rewriter, and
# conflict_resolver.
RSpec.describe "CodeGenerators safety hardening" do
  describe CodeGenerators::Shared::ConditionBuilder do
    let(:host) do
      Class.new do
        include CodeGenerators::Shared::OperandConverter
        include CodeGenerators::Shared::ConditionBuilder
      end.new
    end

    it "refuses to build an attacker-controlled countOperator" do
      expect {
        host.build_query_count_condition({
          "queryConfig" => { "entityId" => 5 },
          "countOperator" => "); system('rm -rf /'); (",
          "countValue" => 3
        })
      }.to raise_error(ArgumentError, /unknown count operator/)
    end

    it "builds every count operator" do
      CodeGenerators::ConditionOperators::COUNT.each do |operator|
        sql = host.build_query_count_condition({
          "queryConfig" => { "entityId" => 1 },
          "countOperator" => operator,
          "countValue" => 0
        })
        expect(sql).to include("total_count #{operator} 0")
      end
    end
  end

  describe CodeGenerators::Shared::OperandConverter do
    include described_class

    it "coerces a Numeric operand to its decimal form without raising" do
      expect(condition_operand_to_ruby(5)).to eq("5")
      expect(condition_operand_to_ruby(3.14)).to eq("3.14")
    end

    it "returns nil for an empty string operand" do
      expect(condition_operand_to_ruby("")).to eq("nil")
    end
  end

  describe CodeGenerators::Shared::CtxReader do
    include described_class

    it "refuses to splice a dotted path containing non-identifier segments" do
      # Without the safety guard a payload like below would produce a
      # `ctx.dig(:items]; system('id'); ctx[:foo)` expression at codegen.
      expect(safe_read("items]; system('id'); ctx[:foo")).to eq("nil")
    end

    it "still produces ctx.dig for a clean dotted path" do
      expect(safe_read("user.profile.id")).to eq("FlowchartRuntime::Step.dig(ctx[:user], :profile, :id)")
    end
  end

  describe CodeGenerators::EmissionRewriter do
    it "drops a renamed_to target that would inject Ruby" do
      list = [
        { "pin" => "model", "renamed_to" => "x]; system('id'); ctx[:y" },
        { "pin" => "other", "renamed_to" => "safe_name" }
      ]
      result = described_class.index_overrides(list, "renamed_to")
      expect(result).to eq("other" => "safe_name")
      expect(result).not_to have_key("model")
    end

    it "drops an override_key target that isn't a Ruby identifier (empty stays as tombstone)" do
      list = [
        { "pin" => "a", "override_key" => "" },             # tombstone — kept
        { "pin" => "b", "override_key" => "valid_key" },    # safe — kept
        { "pin" => "c", "override_key" => "1bad" },         # leading digit — dropped
        { "pin" => "d", "override_key" => "x]; sys()" }     # injection — dropped
      ]
      result = described_class.index_overrides(list, "override_key", allow_empty: true)
      expect(result).to eq("a" => "", "b" => "valid_key")
    end
  end

  describe CodeGenerators::ConflictResolver do
    it "deduplicates repeated (element_id, pin) emissions" do
      result = described_class.call([
        { id: "a", outputs: [{ pin: "model" }, { pin: "model" }] }
      ])
      # A single element listing the same pin twice does not count as a
      # collision — it must collide with a DIFFERENT element.
      expect(result).to eq({})
    end

    it "is stable when two emitters share Float::INFINITY topo position" do
      result1 = described_class.call(
        [
          { id: "z", outputs: [{ pin: "x" }] },
          { id: "a", outputs: [{ pin: "x" }] }
        ],
        topo_order: [] # neither id is in topo
      )
      result2 = described_class.call(
        [
          { id: "z", outputs: [{ pin: "x" }] },
          { id: "a", outputs: [{ pin: "x" }] }
        ],
        topo_order: []
      )
      # The same input must produce the same rename map across runs —
      # otherwise generated files churn between equivalent inputs.
      expect(result1).to eq(result2)
    end
  end

  describe CodeGenerators::MetadataDSL do
    it "returns a frozen copy from to_h so the source @data hash stays mutable" do
      dsl = described_class.new
      dsl.description "first"
      h1 = dsl.to_h
      expect(h1).to be_frozen
      # A second field set after to_h would have raised FrozenError before.
      expect { dsl.description "second" }.not_to raise_error
      expect(dsl.to_h[:description]).to eq("second")
    end
  end

  # --------------------------------------------------------------------------
  # Config-value injection hardening.
  #
  # Every field below is spliced by some generator into emitted Ruby in *code*
  # position (an operand, a hash-key label, an identifier, a comment). Each
  # example drives the real generator through the conformance harness with an
  # adversarial payload and asserts BOTH that the emitted activity still
  # compiles AND that the payload never lands as executable code.
  # --------------------------------------------------------------------------
  describe "config value injection" do
    PAYLOADS = {
      "bracket escape" => 'x]; Kernel.raise("INJMARK"); ctx[:y',
      "paren escape" => '1); Kernel.raise("INJMARK"); (',
      "quote escape" => 'a"); Kernel.raise("INJMARK"); ("',
      "newline escape" => %(a\nKernel.raise("INJMARK")\n),
      "interpolation escape" => 'a#{Kernel.raise("INJMARK")}b',
      "comment escape" => %(a\n# x\nKernel.raise("INJMARK"))
    }.freeze

    # Emitted source in which INJMARK, if present at all, only appears inside a
    # string literal or a comment — never as a token the VM would execute.
    def expect_neutralised(source)
      expect(source).not_to start_with("CONFORMANCE_EMISSION_ERROR")
      expect(Ripper.sexp(source)).not_to(be_nil, "emitted source does not parse:\n#{source}")

      kinds = Ripper.lex(source)
                    .select { |(_pos, _type, tok, _state)| tok.to_s.include?("INJMARK") }
                    .map { |(_pos, type, _tok, _state)| type }.uniq
      expect(kinds - %i[on_tstring_content on_comment]).to(
        be_empty, "INJMARK reached code position (#{kinds.inspect}) in:\n#{source}"
      )
    end

    def emit_with(action_key, field_key, value)
      klass = CodeGenerators::GeneratorRegistry.step_action_generators[action_key]
      field = GeneratorConformance.ui_fields(action_key).find { |f| f[:key].to_s == field_key }
      raise "no field #{action_key}.#{field_key}" if field.nil?

      base = GeneratorConformance.visible_baseline(klass, field)
      probe = if field[:type].to_s == "key_value_list"
        [{ "key" => value, "value" => value }]
      elsif field[:type].to_s == "conditions"
        { "type" => "group", "joins" => [], "conditions" => [{ "field" => value, "operator" => "eq", "value" => value }] }
      else
        value
      end
      config = base.merge(field_key => probe)
      errors = GeneratorConformance.validation_errors(klass, config)
      return :rejected if errors.any?

      GeneratorConformance.emit(klass, config)
    rescue CodeGenerators::GeneratorError, GeneratorConformance::Error, ArgumentError
      :rejected
    end

    {
      "api_call" => %w[authToken authUsername authPassword responseParseKey],
      "hash_manipulate" => %w[renameMap computedFields],
      "filter_collection" => %w[filterField],
      "template_render" => %w[variables],
      "serialize_data" => %w[rootElement],
      "query_models" => %w[orderBy],
      "generate_token" => %w[claims],
      "verify_token" => %w[requiredClaims],
      "audit_log" => %w[metadata],
      "i18n_translate" => %w[interpolations]
    }.each do |action_key, field_keys|
      field_keys.each do |field_key|
        PAYLOADS.each do |name, payload|
          it "neutralises a #{name} in #{action_key}.#{field_key}" do
            source = emit_with(action_key, field_key, payload)
            next expect(source).to eq(:rejected) if source == :rejected

            expect_neutralised(source)
          end
        end
      end
    end

    PAYLOADS.each do |name, payload|
      it "rejects a #{name} in batch_operation.conditions before emitting any artifacts" do
        klass = CodeGenerators::ElementTypes::Process::ModelOperations::BatchOperationGenerator
        config = klass.sample_input.merge(
          "operationType" => "destroy_all",
          "conditions" => [{ "key" => payload, "value" => payload }]
        )
        result = CodeGenerators::TestRunner.execute(klass, config: config)
        messages = Array(result[:validation_errors]).map { |error| error.respond_to?(:message) ? error.message : error.to_s }
        expect(messages.join).to match(/conditions/)
        expect(result).to include(body: nil, code: nil, inputs: [], outputs: [])
        expect(result).not_to have_key(:outcome)
      end
    end
  end

  describe CodeGenerators::Shared::ExpressionSafety do
    let(:host) { Class.new { include CodeGenerators::Shared::ExpressionSafety }.new }

    it "accepts legitimate single expressions" do
      ["ctx[:items]", "acc + item[:amount].to_f", "a.b.c || []", "1 + 2"].each do |expr|
        expect(host.safe_expression?(expr)).to be(true), expr
      end
    end

    it "rejects anything that is not exactly one statement" do
      [
        '1); Kernel.raise("INJMARK"); (',
        'x]; Kernel.raise("INJMARK")',
        "a; b",
        "a\nb",
        "a\n# c\nKernel.raise(1)",
        "",
        "   "
      ].each do |expr|
        expect(host.safe_expression?(expr)).to be(false), expr.inspect
      end
    end

    it "returns the default rather than the payload for unsafe source" do
      expect(host.safe_expression_source("a; b", default: "nil")).to eq("nil")
      expect(host.safe_expression("a; b")).to eq("nil")
      expect(host.safe_expression("ctx[:x]")).to eq("(ctx[:x])")
    end

    it "collapses newlines so a value cannot terminate an emitted comment" do
      expect(host.safe_comment_text("utf-8\nKernel.raise(1)")).not_to include("\n")
    end
  end

  describe CodeGenerators::Shared::IdentifierSanitizer do
    let(:host) { Class.new { include CodeGenerators::Shared::IdentifierSanitizer }.new }

    it "falls back to the default for a non-identifier ctx variable name" do
      expect(host.safe_ident("a].foo; ctx[:b", default: "result")).to eq("result")
      expect(host.safe_ident("end", default: "result")).to eq("result")
      expect(host.safe_ident("total_count", default: "result")).to eq("total_count")
    end

    it "accepts data keys that are not valid locals but rejects punctuation" do
      expect(host.safe_key?("End")).to be(true)
      expect(host.safe_key?("a]; b")).to be(false)
    end

    it "drops unsafe entries when emitting a symbol list" do
      expect(host.safe_symbols(["id", "a]; Kernel.raise(1)", "name"])).to eq(":id, :name")
    end
  end
end
