# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ConfigSchema do
  def schema(&block)
    described_class.new.tap { |s| s.instance_eval(&block) }
  end

  describe "bespoke validate blocks" do
    let(:s) do
      schema do
        enum :op, %w[count custom]
        validate do |cfg, errors|
          errors << "expr required" if cfg["op"] == "custom" && cfg["expr"].blank?
        end
      end
    end

    it "runs role checks and cross-field rules together" do
      expect(s.validate_config("op" => "custom").map(&:message)).to eq(["expr required"])
      expect(s.validate_config("op" => "custom", "expr" => "1+1")).to eq([])
      expect(s.validate_config("op" => "bogus").map(&:code)).to eq([:not_in_list])
    end

    it "evaluates blocks against the given context so they can call its helpers" do
      zoned = schema do
        validate do |cfg, errors|
          errors << "bad tz" unless valid_zone?(cfg["tz"])
        end
      end
      helper_host = Class.new { def valid_zone?(tz) = tz == "UTC" }.new

      expect(zoned.validate_config({ "tz" => "UTC" }, helper_host)).to eq([])
      expect(zoned.validate_config({ "tz" => "Mars" }, helper_host).map(&:message)).to eq(["bad tz"])
    end
  end

  describe "#catalog" do
    it "exposes a machine-readable field list" do
      s = schema { enum :mode, %w[a b], required: true, default: "a" }
      expect(s.catalog).to eq([
        { name: "mode", role: :enum, options: { values: %w[a b], required: true, default: "a", group: :main }, conditions: [], capabilities: [] }
      ])
    end
  end

  describe "role DSL" do
    def ported_schema(&block)
      described_class.new(action_name: "phase3_fixture").tap { |s| s.instance_eval(&block) }
    end

    def error_codes(errors)
      errors.map { |error| [error.field, error.code] }
    end

    it "raises at load time for an unknown role" do
      expect { ported_schema { mystery :x } }
        .to raise_error(ArgumentError, /unknown config_schema role/)
    end

    it "raises at load time for an unknown option" do
      expect { ported_schema { input :x, banana: true } }
        .to raise_error(ArgumentError, /unknown option/)
    end

    it "rejects a reserved output name and allows model/contract" do
      s = ported_schema do
        output :resultVar
      end
      expect(error_codes(s.validate_config("resultVar" => "result"))).to include(["resultVar", :reserved_name])
      expect(error_codes(s.validate_config("resultVar" => "params"))).to include(["resultVar", :reserved_name])
      expect(s.validate_config("resultVar" => "model")).to eq([])
      expect(s.validate_config("resultVar" => "contract")).to eq([])
    end

    it "rejects an invalid or over-long input path" do
      s = ported_schema { input :sourceVariable }
      expect(error_codes(s.validate_config("sourceVariable" => "params.email"))).to eq([])
      expect(error_codes(s.validate_config("sourceVariable" => "a.b.c.d.e"))).to include(["sourceVariable", :invalid_identifier])
      expect(error_codes(s.validate_config("sourceVariable" => "errors.foo"))).to include(["sourceVariable", :reserved_name])
    end

    it "validates an expression as one safe statement" do
      s = ported_schema { expression :predicate }
      expect(s.validate_config("predicate" => "item[:qty] > 0")).to eq([])
      expect(error_codes(s.validate_config("predicate" => "1; Kernel.exit"))).to include(["predicate", :invalid_expression])
    end

    it "validates enum, flag, integer, decimal, template, and localized_text" do
      s = ported_schema do
        enum :operation, %w[sum avg], default: "sum"
        flag :skipNil, default: true
        integer :limit, min: 1, max: 10
        decimal :rate, min: 0, max: 1
        template :message
        localized_text :title
      end
      expect(error_codes(s.validate_config("operation" => "nope"))).to include(["operation", :not_in_list])
      expect(error_codes(s.validate_config("skipNil" => "yes"))).to include(["skipNil", :not_boolean])
      expect(error_codes(s.validate_config("limit" => 99))).to include(["limit", :out_of_range])
      expect(error_codes(s.validate_config("rate" => "x"))).to include(["rate", :invalid_decimal])
      expect(error_codes(s.validate_config("message" => "{{"))).to include(["message", :invalid_template])
      expect(error_codes(s.validate_config("title" => { "zh-CN" => "标题" }))).to include(["title", :en_required])
    end

    it "hides a field that is not visible and returns its default from #value" do
      s = ported_schema do
        enum :rateSource, %w[fixed live], default: "live"
        literal :fixedRate, default: "1.0", visible: { rateSource: "fixed" }
      end
      expect(s.validate_config("rateSource" => "live", "fixedRate" => "")).to eq([])
      expect(s.value({ "rateSource" => "live", "fixedRate" => "9" }, :fixedRate)).to eq("1.0")
      expect(error_codes(s.validate_config("rateSource" => "fixed", "fixedRate" => "x" * 0))).to eq([])
    end

    it "requires a field when the requires statement matches" do
      s = ported_schema do
        enum :rateSource, %w[fixed live], default: "live"
        literal :fixedRate
        requires :fixedRate, when: { rateSource: "fixed" }
      end
      expect(error_codes(s.validate_config("rateSource" => "fixed"))).to include(["fixedRate", :required])
      expect(s.validate_config("rateSource" => "live")).to eq([])
    end

    it "rejects transport retry on a non-idempotent config" do
      s = ported_schema do
        enum :operation, %w[sum avg], default: "sum"
        literal :idempotencyKey
        transport_retry idempotent_when: { operation: %w[sum] }, or_present: :idempotencyKey
      end
      expect(s.validate_config("operation" => "avg", "retryOnTransportError" => true))
        .to include(have_attributes(code: :retry_not_idempotent, field: "retryOnTransportError"))
      expect(s.validate_config("operation" => "sum", "retryOnTransportError" => true)).to eq([])
      expect(s.validate_config("operation" => "avg", "retryOnTransportError" => true, "idempotencyKey" => "k")).to eq([])
    end

    it "rejects connect+read timeouts above the run cap" do
      s = ported_schema { timeouts open: 3, read: 7 }
      expect(s.validate_config("connectTimeout" => 5, "readTimeout" => 6))
        .to include(have_attributes(code: :timeout_exceeds_run_limit))
      expect(s.validate_config("connectTimeout" => 3, "readTimeout" => 7)).to eq([])
    end

    it "derives defaults and sample_input from declarations" do
      s = ported_schema do
        input :sourceVariable, required: true, example: "order.items"
        output :resultVar, default: "total"
      end
      expect(s.defaults).to eq("resultVar" => "total")
      expect(s.sample_input).to eq("sourceVariable" => "order.items", "resultVar" => "total")
      expect(error_codes(s.validate_config(s.defaults))).to eq([["sourceVariable", :required]])
      expect(s.validate_config(s.sample_input)).to eq([])
    end

    it "keeps hidden fields in #examples but out of #sample_input" do
      s = ported_schema do
        enum :rateSource, %w[fixed live], default: "live"
        literal :fixedRate, example: "1.25", visible: { rateSource: "fixed" }
      end
      expect(s.examples).to eq("rateSource" => "live", "fixedRate" => "1.25")
      expect(s.sample_input).to eq("rateSource" => "live")
    end

    it "looks up error messages from shared keys" do
      s = ported_schema { input :sourceVariable, required: true }
      error = s.validate_config({}).first
      expect(error.message).to eq(I18n.t("flowchart_actions.shared.errors.required", field: "sourceVariable"))
    end

    it "seeds only visible defaults" do
      s = ported_schema do
        enum :responseType, %w[none value], default: "none"
        expression :returnValue, default: "ctx.result", visible: { responseType: "value" }
      end
      expect(s.visible_defaults).to eq("responseType" => "none")
    end

    it "accepts an omitted required field when a default is declared" do
      s = ported_schema do
        enum :responseType, %w[none value], default: "none", required: true
      end
      expect(s.validate_config({})).to eq([])
    end

    it "reports undeclared keys on element schemas" do
      s = described_class.new(action_name: "start", i18n_prefix: "flowchart_elements")
      errors = s.validate_config("triggerType" => "http")
      expect(errors).to include(have_attributes(field: "triggerType", code: :unknown_field))
      expect(errors.first.message).to eq(I18n.t("flowchart_elements.shared.errors.unknown_field", field: "triggerType"))
    end

    it "does not report undeclared keys on step-action schemas" do
      s = ported_schema { input :sourceVariable }
      expect(s.validate_config("sourceVariable" => "params.email", "legacyKey" => "x")).to eq([])
    end

    it "exposes fields with name, role, options, conditions, and capabilities" do
      s = ported_schema do
        input :sourceVariable, required: true, example: "order.items"
        transport_retry idempotent_when: { operation: %w[sum] }, or_present: :idempotencyKey
      end
      source = s.fields.find { |field| field.name == "sourceVariable" }
      expect(source.role).to eq(:input)
      expect(source.options[:required]).to eq(true)
      expect(source.options[:example]).to eq("order.items")
      expect(source.conditions).to eq([])
      expect(source.capabilities).to eq([])
      retry_flag = s.fields.find { |field| field.name == "retryOnTransportError" }
      expect(retry_flag.capabilities).to eq([:transport_retry])
      expect(s.capabilities[:transport_retry][:or_present]).to eq("idempotencyKey")
    end
  end

  describe "Phase3FixtureGenerator" do
    it "declares every role" do
      roles = Phase3FixtureGenerator._config_schema.fields.map(&:role)
      expect(roles).to include(
        :input, :output, :expression, :literal, :template, :enum, :flag,
        :integer, :decimal, :list, :mapping, :conditions, :entity_attribute,
        :reference, :localized_text
      )
    end

    it "accepts its derived sample_input" do
      sample = Phase3FixtureGenerator.sample_input
      expect(Phase3FixtureGenerator.new({ "config" => sample }, {}).validate_config(sample)).to eq([])
    end
  end

  it "keeps English and Simplified Chinese shared error keys in parity" do
    english = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_actions_shared.en.yml"))
    chinese = YAML.safe_load_file(Rails.root.join("config/locales/flowchart_actions_shared.zh-CN.yml"))
    expect(chinese.fetch("zh-CN").fetch("flowchart_actions").fetch("shared").fetch("errors").keys)
      .to eq(english.fetch("en").fetch("flowchart_actions").fetch("shared").fetch("errors").keys)
    expect(chinese.fetch("zh-CN").fetch("flowchart_actions").fetch("shared").fetch("fields").keys)
      .to eq(english.fetch("en").fetch("flowchart_actions").fetch("shared").fetch("fields").keys)
  end
end

