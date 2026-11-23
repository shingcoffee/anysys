# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ValidatorRegistry do
  describe 'constants' do
    describe 'VALIDATOR_LABELS' do
      it 'maps all validator keys to display labels' do
        expect(ValidatorRegistry::VALIDATOR_LABELS).to be_a(Hash)
        expect(ValidatorRegistry::VALIDATOR_LABELS).to be_frozen
      end

      it 'maps presence to a stable :required symbol (translated at call time via validator_label)' do
        expect(ValidatorRegistry::VALIDATOR_LABELS["presence"]).to eq(:required)
      end

      it 'maps comparison validators to literal operator strings (not translatable text)' do
        expect(ValidatorRegistry::VALIDATOR_LABELS["greater_than_or_equal_to"]).to eq(">=")
        expect(ValidatorRegistry::VALIDATOR_LABELS["less_than_or_equal_to"]).to eq("<=")
        expect(ValidatorRegistry::VALIDATOR_LABELS["equal_to"]).to eq("==")
        expect(ValidatorRegistry::VALIDATOR_LABELS["not_equal_to"]).to eq("!=")
        expect(ValidatorRegistry::VALIDATOR_LABELS["greater_than"]).to eq(">")
        expect(ValidatorRegistry::VALIDATOR_LABELS["less_than"]).to eq("<")
      end

      it 'maps format validators to stable symbols' do
        expect(ValidatorRegistry::VALIDATOR_LABELS["format_email"]).to eq(:email)
        expect(ValidatorRegistry::VALIDATOR_LABELS["format_url"]).to eq(:url)
        expect(ValidatorRegistry::VALIDATOR_LABELS["format_phone"]).to eq(:phone)
        expect(ValidatorRegistry::VALIDATOR_LABELS["format_custom"]).to eq(:regex)
      end

      it 'maps length validators to stable symbols' do
        expect(ValidatorRegistry::VALIDATOR_LABELS["length_minimum"]).to eq(:min_len)
        expect(ValidatorRegistry::VALIDATOR_LABELS["length_maximum"]).to eq(:max_len)
        expect(ValidatorRegistry::VALIDATOR_LABELS["length_in_range"]).to eq(:len_range)
      end

      it 'maps numeric validators to stable symbols' do
        expect(ValidatorRegistry::VALIDATOR_LABELS["numericality"]).to eq(:numeric)
        expect(ValidatorRegistry::VALIDATOR_LABELS["numericality_integer"]).to eq(:integer)
      end

      it 'maps list validators to stable symbols' do
        expect(ValidatorRegistry::VALIDATOR_LABELS["inclusion"]).to eq(:in_list)
        expect(ValidatorRegistry::VALIDATOR_LABELS["exclusion"]).to eq(:not_in)
      end
    end

    describe 'VALIDATORS' do
      it 'contains runtime validation procs' do
        expect(ValidatorRegistry::VALIDATORS).to be_a(Hash)
        expect(ValidatorRegistry::VALIDATORS).to be_frozen
      end

      it 'returns hash-based validation options' do
        expect(ValidatorRegistry::VALIDATORS[:presence].call).to eq({ presence: true })
      end

      it 'supports parameterized validators' do
        expect(ValidatorRegistry::VALIDATORS[:greater_than].call(10)).to eq({ numericality: { greater_than: 10 } })
        expect(ValidatorRegistry::VALIDATORS[:length_minimum].call(5)).to eq({ length: { minimum: 5 } })
      end
    end

    describe 'VALIDATORS_CODE' do
      it 'contains code-generation string procs' do
        expect(ValidatorRegistry::VALIDATORS_CODE).to be_a(Hash)
        expect(ValidatorRegistry::VALIDATORS_CODE).to be_frozen
      end

      it 'returns string-based validation code' do
        expect(ValidatorRegistry::VALIDATORS_CODE[:presence].call).to eq("presence: true")
      end

      it 'supports parameterized code generation' do
        expect(ValidatorRegistry::VALIDATORS_CODE[:greater_than].call(10)).to eq("numericality: { greater_than: 10 }")
        expect(ValidatorRegistry::VALIDATORS_CODE[:length_minimum].call(5)).to eq("length: { minimum: 5 }")
      end
    end

    describe 'MERGEABLE_VALIDATORS' do
      it 'includes numericality and length' do
        expect(ValidatorRegistry::MERGEABLE_VALIDATORS).to contain_exactly("numericality", "length")
      end
    end

    describe 'VALIDATOR_CONFIG_TYPES' do
      it 'maps validators to their configuration types' do
        expect(ValidatorRegistry::VALIDATOR_CONFIG_TYPES["greater_than"]).to eq("single_value")
        expect(ValidatorRegistry::VALIDATOR_CONFIG_TYPES["length_in_range"]).to eq("range")
        expect(ValidatorRegistry::VALIDATOR_CONFIG_TYPES["format_custom"]).to eq("pattern")
        expect(ValidatorRegistry::VALIDATOR_CONFIG_TYPES["inclusion"]).to eq("list")
      end
    end
  end

  describe '.validator_label' do
    it 'returns display label for known validator' do
      expect(described_class.validator_label("presence")).to eq("Required")
      expect(described_class.validator_label("greater_than")).to eq(">")
    end

    it 'handles symbol input' do
      expect(described_class.validator_label(:presence)).to eq("Required")
    end

    it 'returns original value for unknown validator' do
      expect(described_class.validator_label("custom_validator")).to eq("custom_validator")
    end
  end

  describe '.labels_for_js' do
    it 'maps JS validator types to call-time translated labels' do
      map = described_class.labels_for_js
      expect(map["presence"]).to eq("Required")
      expect(map["greater_than"]).to eq(">")
      expect(map["format_email"]).to eq("Email")
    end

    it 'translates worded labels under zh-CN without changing operators' do
      I18n.with_locale(:"zh-CN") do
        map = described_class.labels_for_js
        expect(map["presence"]).to eq("必填")
        expect(map["greater_than"]).to eq(">")
      end
    end
  end

  describe '.build_validator_display_label' do
    it 'returns base label when no config' do
      expect(described_class.build_validator_display_label("presence", nil)).to eq("Required")
    end

    it 'includes range for length_in_range' do
      config = { "min" => 1, "max" => 20 }
      expect(described_class.build_validator_display_label("length_in_range", config)).to eq("LenRange (1-20)")
    end

    it 'includes value for comparison validators' do
      config = { "value" => 18 }
      expect(described_class.build_validator_display_label("greater_than", config)).to eq("> 18")
      expect(described_class.build_validator_display_label("greater_than_or_equal_to", config)).to eq(">= 18")
    end

    it 'includes value for length validators' do
      config = { "value" => 5 }
      expect(described_class.build_validator_display_label("length_minimum", config)).to eq("MinLen 5")
    end

    it 'includes pattern for format_custom' do
      config = { "pattern" => "^[A-Z]+" }
      expect(described_class.build_validator_display_label("format_custom", config)).to eq("Regex (^[A-Z]+)")
    end

    it 'includes count for inclusion/exclusion with array values' do
      config = { "values" => ["a", "b", "c"] }
      expect(described_class.build_validator_display_label("inclusion", config)).to eq("InList (3 items)")
    end

    it 'includes count for inclusion/exclusion with string values' do
      config = { "values" => "a\nb\nc" }
      expect(described_class.build_validator_display_label("exclusion", config)).to eq("NotIn (3 items)")
    end

    it 'returns base label when config values are missing' do
      expect(described_class.build_validator_display_label("length_in_range", {})).to eq("LenRange")
      expect(described_class.build_validator_display_label("greater_than", {})).to eq(">")
    end
  end

  describe 'inclusion in classes' do
    it 'makes constants accessible to including classes' do
      expect(EntityEntryContract::VALIDATORS).to eq(ValidatorRegistry::VALIDATORS)
      expect(EntityEntryContract::VALIDATOR_LABELS).to eq(ValidatorRegistry::VALIDATOR_LABELS)
    end
  end

  # ── VALIDATORS runtime lambda coverage ────────────────────────────────────

  describe 'VALIDATORS lambda invocations' do
    let(:v) { ValidatorRegistry::VALIDATORS }

    it 'presence' do
      expect(v[:presence].call).to eq({ presence: true })
    end

    it 'numericality validators with default value' do
      expect(v[:greater_than_or_equal_to].call).to eq({ numericality: { greater_than_or_equal_to: 0 } })
      expect(v[:less_than_or_equal_to].call).to   eq({ numericality: { less_than_or_equal_to: 0 } })
      expect(v[:equal_to].call).to                eq({ numericality: { equal_to: 0 } })
      expect(v[:not_equal_to].call).to            eq({ numericality: { other_than: 0 } })
      expect(v[:greater_than].call).to            eq({ numericality: { greater_than: 0 } })
      expect(v[:less_than].call).to               eq({ numericality: { less_than: 0 } })
    end

    it 'format validators' do
      expect(v[:format_email].call).to  have_key(:format)
      expect(v[:format_url].call).to    have_key(:format)
      expect(v[:format_phone].call).to  have_key(:format)
      expect(v[:format_custom].call).to have_key(:format)
    end

    it 'length validators with default values' do
      expect(v[:length_minimum].call).to   eq({ length: { minimum: 1 } })
      expect(v[:length_maximum].call).to   eq({ length: { maximum: 255 } })
      expect(v[:length_in_range].call).to  eq({ length: { in: 1..255 } })
    end

    it 'numericality flags' do
      expect(v[:numericality].call).to         eq({ numericality: true })
      expect(v[:numericality_integer].call).to eq({ numericality: { only_integer: true } })
    end

    it 'inclusion/exclusion with default empty array' do
      expect(v[:inclusion].call).to eq({ inclusion: { in: [] } })
      expect(v[:exclusion].call).to eq({ exclusion: { in: [] } })
    end

    it 'acceptance' do
      expect(v[:acceptance].call).to eq({ acceptance: true })
    end
  end

  # ── VALIDATORS_CODE lambda coverage ────────────────────────────────────────

  describe 'VALIDATORS_CODE lambda invocations' do
    let(:vc) { ValidatorRegistry::VALIDATORS_CODE }

    it 'format lambdas return expected strings' do
      expect(vc[:format_email].call).to  include("URI::MailTo::EMAIL_REGEXP")
      expect(vc[:format_url].call).to    include("http https")
      expect(vc[:format_phone].call).to  include("\\d")
      expect(vc[:format_custom].call).to eq("format: { with: // }")
    end

    it 'length_in_range with default' do
      expect(vc[:length_in_range].call).to eq("length: { in: 1..255 }")
    end

    it 'inclusion/exclusion with default' do
      expect(vc[:inclusion].call).to eq("inclusion: { in: [] }")
      expect(vc[:exclusion].call).to eq("exclusion: { in: [] }")
    end

    it 'numericality and acceptance' do
      expect(vc[:numericality].call).to         eq("numericality: true")
      expect(vc[:numericality_integer].call).to eq("numericality: { only_integer: true }")
      expect(vc[:acceptance].call).to           eq("acceptance: true")
    end
  end

  # ── build_validator_display_label uncovered branches ──────────────────────

  describe '.build_validator_display_label edge cases' do
    it 'returns base label for length_in_range when min missing' do
      # config has max but not min
      expect(described_class.build_validator_display_label("length_in_range", { "max" => 10 })).to eq("LenRange")
    end

    it 'returns base label for length_in_range when max missing' do
      expect(described_class.build_validator_display_label("length_in_range", { "min" => 1 })).to eq("LenRange")
    end

    it 'returns base label for format_custom when pattern is absent' do
      expect(described_class.build_validator_display_label("format_custom", {})).to eq("Regex")
    end

    it 'returns base label for inclusion/exclusion when values key absent' do
      expect(described_class.build_validator_display_label("inclusion", {})).to eq("InList")
      expect(described_class.build_validator_display_label("exclusion", {})).to eq("NotIn")
    end

    it 'returns base label for the else branch (unknown validator type with config)' do
      # Hits the else arm in the case statement — unknown type returns plain base_label
      expect(described_class.build_validator_display_label("numericality", { "value" => 5 })).to eq("Numeric")
      expect(described_class.build_validator_display_label("presence", { "value" => true })).to eq("Required")
    end
  end
end
