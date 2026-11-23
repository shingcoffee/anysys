# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::ConfigurationValidator do
  def config(rules: [], calculations: [], fields: [])
    {
      "pages" => [{ "id" => "p1", "name" => "Page 1", "fields" => fields }],
      "rules" => rules,
      "calculations" => calculations
    }
  end

  let(:fields) do
    [
      { "id" => "price",   "label" => "Price",   "property_type" => "number" },
      { "id" => "qty",     "label" => "Qty",     "property_type" => "number" },
      { "id" => "country", "label" => "Country", "property_type" => "select" }
    ]
  end

  it "is valid and error-free when initialized with nil (no configuration)" do
    validator = described_class.new(nil)
    expect(validator.valid?).to be(true)
    expect(validator.errors).to be_empty
  end

  it "passes when all condition field_ids exist" do
    rules = [{ "id" => "r1", "enabled" => true,
               "conditions" => { "logic" => "all", "groups" => [
                 { "logic" => "all", "items" => [
                   { "field_id" => "country", "operator" => "equals", "value" => "US" }
                 ] } ] },
               "actions" => [{ "type" => "show_field", "target_id" => "price" }] }]
    validator = described_class.new(config(rules: rules, fields: fields))
    expect(validator.valid?).to be(true)
    expect(validator.errors).to be_empty
  end

  it "flags a condition referencing an unknown field" do
    rules = [{ "id" => "r1", "enabled" => true,
               "conditions" => { "logic" => "all", "groups" => [
                 { "logic" => "all", "items" => [
                   { "field_id" => "ghost", "operator" => "equals", "value" => "x" }
                 ] } ] },
               "actions" => [{ "type" => "show_field", "target_id" => "price" }] }]
    validator = described_class.new(config(rules: rules, fields: fields))
    expect(validator.valid?).to be(false)
    expect(validator.errors.join).to match(/unknown field 'ghost'/i)
  end

  it "flags an action targeting an unknown field" do
    rules = [{ "id" => "r1", "enabled" => true,
               "conditions" => { "logic" => "all", "groups" => [] },
               "actions" => [{ "type" => "show_field", "target_id" => "ghost" }] }]
    validator = described_class.new(config(rules: rules, fields: fields))
    expect(validator.valid?).to be(false)
    expect(validator.errors.join).to match(/action.*unknown field 'ghost'/i)
  end

  describe "calculations" do
    it "flags a formula referencing an unknown field" do
      calcs = [{ "id" => "c1", "target_field_id" => "price", "formula" => "{ghost} * 2" }]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/unknown field 'ghost'/i)
    end

    it "flags an unknown function" do
      calcs = [{ "id" => "c1", "target_field_id" => "price", "formula" => "BOGUS({qty})" }]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/unknown function 'BOGUS'/i)
    end

    it "flags unbalanced parentheses" do
      calcs = [{ "id" => "c1", "target_field_id" => "price", "formula" => "SUM({qty}, 2" }]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/unbalanced/i)
    end

    it "detects a circular dependency between calculations" do
      calcs = [
        { "id" => "c1", "target_field_id" => "price", "formula" => "{qty} + 1" },
        { "id" => "c2", "target_field_id" => "qty",   "formula" => "{price} + 1" }
      ]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/circular/i)
    end

    it "does NOT produce a false 'unknown function' error for a bare underscore token like {price}_(2)" do
      # The expression {price}_(2) contains `_(` which the old /\b([A-Z_]+)\s*\(/
      # regex would never match (no uppercase), but a pure-underscore sequence like
      # `_HELPER(` could slip through. Using a formula that starts with an underscore
      # directly before `(` confirms no spurious error is raised.
      calcs = [{ "id" => "c1", "target_field_id" => "price", "formula" => "{price} * _(2)" }]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      validator.valid?
      # The only errors should be about parentheses, NOT an unknown function '_'
      expect(validator.errors.none? { |e| e.match?(/unknown function '_'/i) }).to be(true)
    end

    it "does NOT flag an unknown function for a leading-underscore identifier like _HELPER(" do
      # Confirms the regex /\b([A-Z][A-Z0-9_]*)\s*\(/ requires a leading uppercase letter
      calcs = [{ "id" => "c1", "target_field_id" => "price", "formula" => "_HELPER({qty})" }]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      validator.valid?
      expect(validator.errors.none? { |e| e.match?(/unknown function/i) }).to be(true)
    end

    it "reports circular dependency only once even with three-node cycles" do
      # A -> B -> C -> A: should produce exactly one circular dependency error
      fields_with_c = fields + [{ "id" => "discount", "label" => "Discount", "property_type" => "number" }]
      calcs = [
        { "id" => "c1", "target_field_id" => "price",    "formula" => "{qty} + 1" },
        { "id" => "c2", "target_field_id" => "qty",      "formula" => "{discount} + 1" },
        { "id" => "c3", "target_field_id" => "discount", "formula" => "{price} + 1" }
      ]
      validator = described_class.new(config(calculations: calcs, fields: fields_with_c))
      validator.valid?
      circular_errors = validator.errors.select { |e| e.match?(/circular/i) }
      expect(circular_errors.length).to eq(1)
    end

    it "flags a calculation missing target_field_id" do
      calcs = [{ "id" => "c1", "formula" => "{qty} + 1" }]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/missing target_field_id/i)
    end

    it "flags a calculation missing formula" do
      calcs = [{ "id" => "c1", "target_field_id" => "price" }]
      validator = described_class.new(config(calculations: calcs, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/missing formula/i)
    end
  end

  describe "rules structural validation" do
    it "flags a rule missing id" do
      rules = [{ "enabled" => true, "conditions" => {}, "actions" => [] }]
      validator = described_class.new(config(rules: rules, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/missing id/i)
    end

    it "flags a rule missing conditions key" do
      rules = [{ "id" => "r1", "enabled" => true, "actions" => [] }]
      validator = described_class.new(config(rules: rules, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/missing conditions/i)
    end

    it "flags a rule missing actions key" do
      rules = [{ "id" => "r1", "enabled" => true, "conditions" => {} }]
      validator = described_class.new(config(rules: rules, fields: fields))
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/missing actions/i)
    end

    it "flags rules when not an array" do
      cfg = config(fields: fields).merge("rules" => "not-an-array")
      validator = described_class.new(cfg)
      expect(validator.valid?).to be(false)
      expect(validator.errors.join).to match(/rules must be an array/i)
    end

    it "does not raise when a rule group or action slot is null" do
      rules = [{ "id" => "r1", "enabled" => true,
                 "conditions" => { "groups" => [nil] },
                 "actions" => [nil] }]
      expect { described_class.new(config(rules: rules, fields: fields)).valid? }.not_to raise_error
    end
  end

  it "does not raise when pages or calculations include a null slot" do
    cfg = config(fields: fields).merge(
      "pages" => [nil, { "id" => "p1", "name" => "Page 1", "fields" => fields }],
      "calculations" => [nil]
    )
    expect { described_class.new(cfg).valid? }.not_to raise_error
  end

  it "rejects a non-object configuration" do
    validator = described_class.new(true)
    expect(validator.valid?).to be(false)
    expect(validator.errors.join).to match(/must be an object/i)
  end
end
