# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sms::Contracts::Send do
  subject(:form) { described_class.new(model) }

  let(:model) do
    OpenStruct.new(to: nil, template_key: nil, vars: nil, idempotency_key: nil)
  end
  let!(:template) { create(:sms_template, key: "verify_code", variables: %w[code], status: "active") }

  # Baseline is a fully valid submission; each example overrides only the field
  # under test via keyword args.
  def validate_with(**overrides)
    form.validate({ to: "+8613800138000", template_key: "verify_code", vars: { code: "1234" } }.merge(overrides))
    form
  end

  describe "to validation" do
    it "accepts an international number" do
      expect(validate_with(to: "+8613800138000").errors[:to]).to be_empty
    end

    it "accepts a domestic number without +" do
      expect(validate_with(to: "13800138000").errors[:to]).to be_empty
    end

    it "rejects a blank to" do
      expect(validate_with(to: "").errors[:to]).not_to be_empty
    end

    it "rejects a non-numeric to" do
      expect(validate_with(to: "not-a-phone").errors[:to]).not_to be_empty
    end

    it "rejects a too-short number" do
      expect(validate_with(to: "12345").errors[:to]).not_to be_empty
    end
  end

  describe "template_key validation" do
    it "rejects blank template_key" do
      expect(validate_with(template_key: "").errors[:template_key]).not_to be_empty
    end

    it "adds error when template is not registered / inactive" do
      expect(validate_with(template_key: "unknown_key").errors[:template_key])
        .to include("is not a registered active template")
    end
  end

  describe "vars validation" do
    it "treats nil vars as empty and reports missing required keys" do
      expect(validate_with(vars: nil).errors[:vars].join).to include("missing required keys")
    end

    it "adds error for missing required keys" do
      expect(validate_with(vars: {}).errors[:vars].join).to include("missing required keys")
    end

    it "adds error for unknown extra keys" do
      expect(validate_with(vars: { code: "1234", extra: "bad" }).errors[:vars].join).to include("unknown keys")
    end

    it "is valid when vars exactly match required keys" do
      expect(validate_with(vars: { code: "1234" }).errors[:vars]).to be_empty
    end

    it "is valid with empty vars when the template has no variables" do
      create(:sms_template, key: "plain_notice", variables: [], status: "active")
      expect(validate_with(template_key: "plain_notice", vars: nil).errors[:vars]).to be_empty
      expect(validate_with(template_key: "plain_notice", vars: {}).errors[:vars]).to be_empty
    end
  end

  describe "shape and payload standards" do
    [[], "code=1234", 42, false].each do |vars|
      it "rejects non-object vars #{vars.inspect} before SQL" do
        expect(Sms::Template).not_to receive(:active)
        expect(validate_with(vars: vars).errors[:vars]).not_to be_empty
      end
    end

    [{ nested: "value" }, ["1234"], nil, true, false, "", "  ", Float::NAN, Float::INFINITY, Complex(1, 2)].each do |value|
      it "rejects nonscalar/blank/nonfinite values #{value.inspect}" do
        expect(Sms::Template).not_to receive(:active)
        expect(validate_with(vars: { code: value }).errors[:vars]).not_to be_empty
      end
    end

    [1234, 0, 1.25, BigDecimal("1.25")].each do |value|
      it "accepts finite numeric value #{value.inspect}" do
        expect(validate_with(vars: { code: value }).errors).to be_empty
      end
    end

    it "enforces the per-value byte limit including multibyte text" do
      expect(validate_with(vars: { code: "a" * 1_024 }).errors).to be_empty
      expect(validate_with(vars: { code: "界" * 342 }).errors[:vars]).not_to be_empty
    end

    it "bounds the complete serialized JSON including escaping" do
      expect(Sms::Template).not_to receive(:active)
      vars = (1..9).to_h { |i| ["key#{i}", "a" * 1_024] }
      expect(validate_with(vars: vars).errors[:vars]).not_to be_empty
      escaped = (1..4).to_h { |i| ["key#{i}", "\x01" * 512] }
      expect(validate_with(vars: escaped).errors[:vars]).not_to be_empty
    end

    it "rejects duplicate string/symbol keys and non-string key shapes" do
      expect(validate_with(vars: { "code" => "1", code: "2" }).errors[:vars]).not_to be_empty
      expect(validate_with(vars: { [] => "1" }).errors[:vars]).not_to be_empty
    end

    [[], {}, 42, "invalid key", "a" * 129].each do |key|
      it "rejects malformed template key #{key.inspect} before SQL" do
        expect(Sms::Template).not_to receive(:active)
        expect(validate_with(template_key: key).errors[:template_key]).not_to be_empty
      end
    end

    [[], {}, 42, "a" * 129, "界" * 43].each do |key|
      it "rejects malformed idempotency key #{key.inspect} before SQL" do
        expect(Sms::Template).not_to receive(:active)
        expect(validate_with(idempotency_key: key).errors[:idempotency_key]).not_to be_empty
      end
    end

    it "accepts a 128-byte idempotency key and treats blank strings as absent" do
      expect(validate_with(idempotency_key: "a" * 128).errors).to be_empty
      expect(validate_with(idempotency_key: " ").errors).to be_empty
      expect(form.idempotency_key).to be_nil
      expect(validate_with(idempotency_key: " " * 129).errors[:idempotency_key]).not_to be_empty
    end

    it "rejects invalid or unsupported string encodings through controlled validation" do
      expect(Sms::Template).not_to receive(:active)
      bad = "\xFF".dup.force_encoding("UTF-8")
      utf16 = "verify_code".encode("UTF-16LE")
      expect(validate_with(template_key: utf16).errors[:template_key]).not_to be_empty
      expect(validate_with(idempotency_key: bad).errors[:idempotency_key]).not_to be_empty
      expect(validate_with(vars: { code: bad }).errors[:vars]).not_to be_empty
    end

    it "rejects arbitrary phone text and recipient arrays before SQL" do
      expect(Sms::Template).not_to receive(:active)
      expect(validate_with(to: "call +8613800138000").errors[:to]).not_to be_empty
      expect(validate_with(to: ["+8613800138000"]).errors[:to]).not_to be_empty
    end

    it "normalizes nil vars to an actual empty object" do
      create(:sms_template, key: "no_vars", variables: [])
      expect(form.validate(to: "+8613800138000", template_key: "no_vars", vars: nil)).to be(true)
      expect(form.vars).to eq({})
    end
  end
end
