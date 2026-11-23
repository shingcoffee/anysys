# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformAnnouncements::CustomerQuery do
  def group(*conditions, joins: nil)
    joins ||= Array.new([conditions.length - 1, 0].max, "AND")
    { "type" => "group", "joins" => joins, "conditions" => conditions }
  end

  def leaf(field, operator, value = "")
    { "field" => field, "operator" => operator, "value" => value }
  end

  def ids_for(rules)
    described_class.call(rules: rules).order(:id).pluck(:id)
  end

  it "matches nobody when rules are empty" do
    create(:customer)
    expect(ids_for({})).to eq([])
    expect(described_class.usable?({})).to be false
  end

  it "matches by customer id" do
    included = create(:customer)
    create(:customer)
    rules = group(leaf("id", "equals", included.id.to_s))

    expect(ids_for(rules)).to eq([ included.id ])
    expect(described_class.matches?(customer_id: included.id, rules: rules)).to be true
  end

  it "matches enum keys such as tier=premium" do
    premium = create(:customer, :premium)
    create(:customer, :basic)
    rules = group(leaf("tier", "equals", "premium"))

    expect(ids_for(rules)).to eq([ premium.id ])
  end

  it "matches industry by enum key" do
    banking = create(:customer, industry: :banking)
    create(:customer, industry: :technology)
    rules = group(leaf("industry", "equals", "banking"))

    expect(ids_for(rules)).to eq([ banking.id ])
  end

  it "matches name contains" do
    acme = create(:customer, name: "Acme Corp")
    create(:customer, name: "Beta LLC")
    rules = group(leaf("name", "contains", "acme"))

    expect(ids_for(rules)).to eq([ acme.id ])
  end

  it "combines AND and OR left-associatively" do
    premium_acme = create(:customer, :premium, name: "Acme")
    basic_acme = create(:customer, :basic, name: "Acme")
    premium_other = create(:customer, :premium, name: "Other")
    rules = group(
      leaf("name", "equals", "Acme"),
      leaf("tier", "equals", "premium"),
      leaf("name", "equals", "Other"),
      joins: %w[AND OR]
    )

    # ((name=Acme AND tier=premium) OR name=Other)
    expect(ids_for(rules)).to contain_exactly(premium_acme.id, premium_other.id)
    expect(ids_for(rules)).not_to include(basic_acme.id)
  end

  it "drops unknown fields instead of interpolating them" do
    create(:customer)
    rules = group(leaf("password", "equals", "secret"))

    expect(ids_for(rules)).to eq([])
    expect(described_class.usable?(rules)).to be false
  end

  it "includes a customer created after the rules were written" do
    rules = group(leaf("tier", "equals", "enterprise"))
    expect(ids_for(rules)).to eq([])

    later = create(:customer, :enterprise)
    expect(ids_for(rules)).to eq([ later.id ])
  end

  describe ".matching_keys" do
    it "evaluates several rule sets against one customer in a single query" do
      target = create(:customer, name: "Target")
      other  = create(:customer, name: "Other")

      keys = described_class.matching_keys(
        customer_id: target.id,
        rules_by_key: {
          hit:   id_rules(target.id),
          miss:  id_rules(other.id),
          hit2:  name_rules("Target")
        }
      )

      expect(keys).to contain_exactly(:hit, :hit2)
    end

    it "drops rule sets that compile to nothing rather than matching everyone" do
      target = create(:customer)

      keys = described_class.matching_keys(
        customer_id: target.id,
        rules_by_key: { empty: {}, unknown_field: unknown_field_rules, real: id_rules(target.id) }
      )

      expect(keys).to eq([ :real ])
    end

    it "returns nothing when there are no compilable rule sets" do
      target = create(:customer)

      expect(described_class.matching_keys(customer_id: target.id, rules_by_key: {})).to eq([])
      expect(described_class.matching_keys(customer_id: target.id, rules_by_key: { a: {} })).to eq([])
    end

    it "returns nothing without a customer id" do
      expect(described_class.matching_keys(customer_id: nil, rules_by_key: { a: id_rules(1) })).to eq([])
    end

    it "returns nothing when the customer row is not visible" do
      target = create(:customer)
      rules  = { a: id_rules(target.id) }

      expect(described_class.matching_keys(customer_id: -1, rules_by_key: rules)).to eq([])
    end
  end

  def id_rules(id)
    {
      "type" => "group", "joins" => [],
      "conditions" => [ { "field" => "id", "operator" => "equals", "value" => id.to_s } ]
    }
  end

  def name_rules(name)
    {
      "type" => "group", "joins" => [],
      "conditions" => [ { "field" => "name", "operator" => "equals", "value" => name } ]
    }
  end

  def unknown_field_rules
    {
      "type" => "group", "joins" => [],
      "conditions" => [ { "field" => "secret_column", "operator" => "equals", "value" => "x" } ]
    }
  end
end
