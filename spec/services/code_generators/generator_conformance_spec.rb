# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/support/generator_conformance").to_s

RSpec.describe GeneratorConformance do
  describe "failure transparency" do
    let(:generator) do
      Class.new(CodeGenerators::BaseGenerator) do
        def self.sample_input = { "mode" => "good" }
        def validate_config(_config) = []
        def generate_body
          raise "emission exploded" if config["mode"] == "bad"

          "true"
        end
      end.tap { |klass| stub_const("ConformanceProbeGenerator", klass) }
    end
    let(:field) { { key: "mode", type: :select, options: [{ value: "good" }, { value: "bad" }] } }

    it "does not count a crashing variant as a changed field" do
      expect { described_class.field_delta(generator, "probe", field) }
        .to raise_error(RuntimeError, /emission exploded/)
    end

    it "does not omit crashing enum options from duplicate detection" do
      expect { described_class.duplicate_enum_options(generator, "probe", field) }
        .to raise_error(RuntimeError, /emission exploded/)
    end

    it "does not convert a validation exception into acceptance" do
      allow_any_instance_of(generator).to receive(:validate_config).and_raise("validation exploded")
      expect { described_class.validation_errors(generator, generator.sample_input) }
        .to raise_error(RuntimeError, /validation exploded/)
    end

    it "validates without emitting an explicitly rejected configuration" do
      allow_any_instance_of(generator).to receive(:validate_config).and_return(["invalid mode"])
      expect(described_class.validation_errors(generator, "mode" => "bad")).to eq(["invalid mode"])
    end

    it "does not accept malformed validator results" do
      allow_any_instance_of(generator).to receive(:validate_config).and_return(nil)
      expect { described_class.validation_errors(generator, generator.sample_input) }
        .to raise_error(GeneratorConformance::Error, /validation_errors/)
    end

    it "does not count invalid Ruby as a changed field" do
      allow_any_instance_of(generator).to receive(:generate_body).and_return("def broken(")
      expect { described_class.emit(generator, generator.sample_input) }
        .to raise_error(CodeGenerators::GeneratorError)
    end

    it "does not silently accept missing source from an action" do
      allow_any_instance_of(generator).to receive(:generate_body).and_return(nil)
      expect { described_class.emit(generator, generator.sample_input) }
        .to raise_error(GeneratorConformance::Error, /source/)
    end

    it "reports a validation transition separately, compiling the accepted variant" do
      allow_any_instance_of(generator).to receive(:validate_config) do |_instance, config|
        config["mode"] == "good" ? ["missing dependent field"] : []
      end
      allow_any_instance_of(generator).to receive(:generate_body).and_return("true")
      expect(described_class.field_delta(generator, "probe", field)).to eq(:validation_changed)
    end

    it "still fails if a validation transition leads to an emission crash" do
      allow_any_instance_of(generator).to receive(:validate_config) do |_instance, config|
        config["mode"] == "good" ? ["missing dependent field"] : []
      end
      expect { described_class.field_delta(generator, "probe", field) }
        .to raise_error(RuntimeError, /emission exploded/)
    end

    it "does not digest rejected enum configurations as if they emitted source" do
      allow_any_instance_of(generator).to receive(:validate_config) do |_instance, config|
        config["mode"] == "bad" ? ["invalid mode"] : []
      end
      expect(described_class.enum_coverage(generator, "probe", field).keys).to eq(["good"])
    end
  end

  describe ".probe_value" do
    it "returns a different select option than the baseline" do
      field = {
        key: "action",
        type: :select,
        options: [{ "value" => "write" }, { "value" => "delete" }]
      }
      expect(described_class.probe_value(field, "write")).to eq("delete")
    end

    it "returns nil for a select with only one option" do
      field = { key: "mode", type: :select, options: [{ "value" => "only" }] }
      expect(described_class.probe_value(field, "only")).to be_nil
    end

    it "returns a numerically different value for a number field" do
      field = { key: "ttl", type: :number }
      expect(described_class.probe_value(field, 3600)).to eq(3607)
    end

    it "returns a distinct string for a text field" do
      field = { key: "cacheKey", type: :text }
      expect(described_class.probe_value(field, "user_data"))
        .to eq("conformance_probe_cacheKey")
    end

    it "returns a populated pair list for a key_value_list field" do
      field = { key: "tags", type: :key_value_list }
      expect(described_class.probe_value(field, nil))
        .to eq([{ "key" => "conformance_probe_tag", "value" => "probe" }])
    end

    it "perturbs an object/expression field with a typed object or safe context reference" do
      field = { key: "smsVars", type: :json_or_expression }
      expect(described_class.probe_value(field, nil)).to eq("conformance_probe_tag" => "probe")
      expect(described_class.probe_value(field, { "code" => "1234" })).to eq("ctx.conformance_probe_smsVars")
    end

    it "returns nil for structural field types it cannot probe" do
      expect(described_class.probe_value({ key: "steps", type: :steps }, nil)).to be_nil
      expect(described_class.probe_value({ key: "branches", type: :branches }, nil)).to be_nil
    end

    it "requires an explicit probe policy for new UI field types" do
      expect { described_class.probe_value({ key: "new", type: :unknown_editor }, nil) }
        .to raise_error(GeneratorConformance::Error, /No conformance probe/)
    end
  end

  describe ".field_delta" do
    let(:generator) { CodeGenerators::ElementTypes::Process::Caching::CacheWriteGenerator }

    it "reports :changed for a field that influences emitted source" do
      field = described_class.ui_fields("cache_write").find { |f| f[:key] == "sourceVariable" }
      expect(described_class.field_delta(generator, "cache_write", field)).to eq(:changed)
    end

    it "reports :skipped for a field it cannot probe" do
      expect(described_class.field_delta(generator, "cache_write", { key: "x", type: :steps }))
        .to eq(:skipped)
    end

    it "compiles SMS template variables under a valid send_sms baseline" do
      send_sms = CodeGenerators::ElementTypes::Process::Communication::SendSmsGenerator
      field = described_class.ui_fields("send_sms").find { |entry| entry[:key] == "vars" }
      baseline = described_class.visible_baseline(send_sms, field)

      expect(described_class.validation_errors(send_sms, baseline)).to be_empty
      expect(described_class.field_delta(send_sms, "send_sms", field)).to eq(:changed)
      expect(described_class.emit(send_sms, baseline.merge(
        "vars" => [{ "key" => "code", "value" => "ctx.code" }]
      ))).to match(/vars:/)
    end
  end

  describe ".enum_coverage" do
    let(:generator) { CodeGenerators::ElementTypes::Process::Caching::CacheWriteGenerator }

    it "emits distinct source for each option of a meaningful select" do
      field = described_class.ui_fields("cache_write").find { |f| f[:key] == "action" }
      digests = described_class.enum_coverage(generator, "cache_write", field)

      expect(digests.keys).to contain_exactly("write", "write_if_absent")
      expect(digests.values.uniq.size).to eq(2)
    end
  end

  describe ".duplicate_enum_options" do
    let(:generator) { CodeGenerators::ElementTypes::Process::Caching::CacheWriteGenerator }

    it "returns no groups when every option emits its own source" do
      field = described_class.ui_fields("cache_write").find { |f| f[:key] == "action" }
      expect(described_class.duplicate_enum_options(generator, "cache_write", field)).to be_empty
    end

    it "groups options the generator cannot distinguish" do
      field = { key: "conformanceUnreadKey", type: :select,
                options: [{ "value" => "alpha" }, { "value" => "beta" }] }

      expect(described_class.duplicate_enum_options(generator, "cache_write", field))
        .to eq([%w[alpha beta]])
    end

    it "only treats an allow-list entry as covering the exact colliding group" do
      stub_const("GeneratorConformance::DUPLICATE_ENUM_OPTION_ALLOWLIST",
                 { "demo" => { "field" => { options: %w[alpha beta], reason: "test" } } })

      expect(described_class.duplicate_enum_allow_listed?("demo", "field", %w[alpha beta])).to be(true)
      expect(described_class.duplicate_enum_allow_listed?("demo", "field", %w[alpha gamma])).to be(false)
      expect(described_class.duplicate_enum_allow_listed?("demo", "other", %w[alpha beta])).to be(false)
    end
  end

  describe ".dead_ui_fields" do
    let(:generator) { CodeGenerators::ElementTypes::Process::Caching::CacheWriteGenerator }

    it "is empty for a generator that references all of its fields" do
      expect(described_class.dead_ui_fields(generator, "cache_write")).to be_empty
    end

    it "reports a declared field no generator source mentions" do
      loop_gen = CodeGenerators::ElementTypes::Loop::LoopGenerator

      fields = [{ key: "loopType", type: :select }, { key: "neverReadByAnyGenerator", type: :text }]
      allow(described_class).to receive(:ui_fields).with("loop").and_return(fields)

      expect(described_class.dead_ui_fields(loop_gen, "loop")).to eq(%w[neverReadByAnyGenerator])
    end

    it "follows mixins so a key read only in an included module is not dead" do
      source = described_class.generator_reference_source(
        CodeGenerators::ElementTypes::Process::Security::EncryptDataGenerator
      )

      expect(source).to include("deriveKeySalt")
      expect(described_class.dead_ui_fields(
               CodeGenerators::ElementTypes::Process::Security::EncryptDataGenerator, "encrypt_data"
             )).to be_empty
    end
  end

  describe ".visibility_leak?" do
    it "is false when a hidden field does not influence emitted source" do
      generator = CodeGenerators::ElementTypes::Process::Communication::ApiCallGenerator
      field = described_class.ui_fields("api_call").find { |f| f[:visibleWhen] }

      expect(described_class.visibility_leak?(generator, "api_call", field)).to be(false)
    end
  end

  # --- Registry-wide sweeps -------------------------------------------------

  CodeGenerators::GeneratorRegistry.step_action_generators.each do |action_key, generator_class|
    describe "#{action_key} (#{generator_class.name})" do
      it "references every property-editor field it declares" do
        expect(GeneratorConformance.dead_ui_fields(generator_class, action_key)).to be_empty,
          "#{action_key} declares property-editor fields no generator source references: " \
          "#{GeneratorConformance.dead_ui_fields(generator_class, action_key).join(', ')}"
      end

      GeneratorConformance.ui_fields(action_key).each do |field|
        field_key = field[:key].to_s

        it "honors the #{field_key} property-editor field" do
          verdict = GeneratorConformance.field_delta(generator_class, action_key, field)

          if GeneratorConformance.allow_listed?(action_key, field_key)
            expect(verdict).to eq(:inert),
              "#{action_key}.#{field_key} is allow-listed as inert but now emits a delta; remove the allow-list entry"
          else
            expect(%i[changed rejected validation_changed skipped]).to include(verdict),
              "#{action_key}.#{field_key} is offered in the property editor but changing it does not change generated code"
          end
        end

        next unless field[:type]&.to_sym == :select || field[:role]&.to_sym == :enum

        it "emits distinct, compilable source for every #{field_key} option" do
          digests = GeneratorConformance.enum_coverage(generator_class, action_key, field)
          next if digests.size < 2

          expect(digests.values.uniq.size).to be > 1,
            "#{action_key}.#{field_key} offers #{digests.size} options that all emit identical source"
        end

        it "emits source unique to each accepted #{field_key} option" do
          groups = GeneratorConformance.duplicate_enum_options(generator_class, action_key, field)
          offenders = groups.reject do |group|
            GeneratorConformance.duplicate_enum_allow_listed?(action_key, field_key, group)
          end

          expect(offenders).to be_empty,
            "#{action_key}.#{field_key} offers options the generator does not distinguish: " \
            "#{offenders.map { |g| g.join(' == ') }.join('; ')}"
        end
      end

      GeneratorConformance.ui_fields(action_key).select { |f| f[:visibleWhen] }.each do |field|
        it "ignores or explicitly rejects #{field[:key]} when its visibleWhen condition is unmet" do
          expect([false, :rejected]).to include(GeneratorConformance.visibility_leak?(generator_class, action_key, field)),
            "#{action_key}.#{field[:key]} is hidden in the editor but still changes generated code"
        end
      end
    end
  end
end
