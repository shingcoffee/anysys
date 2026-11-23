# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Audience::SegmentQuery do
  let_it_be(:customer) { create(:customer) }
  let(:other)    { create(:customer) }

  def query(rules)
    described_class.new(customer: customer, rules: rules).relation
  end

  it "returns all customer users when there are no conditions" do
    u = create(:user, customer: customer)
    other_user = create(:user, customer: other)
    result = query({}).to_a
    expect(result).to include(u)
    expect(result).not_to include(other_user)
    expect(result.map(&:customer_id).uniq).to eq([customer.id])
  end

  it "filters by a scalar User attribute with bound parameters" do
    match = create(:user, customer: customer, first_name: "Ada")
    create(:user, customer: customer, first_name: "Bob")
    rules = { "match" => "all", "conditions" => [{ "field" => "first_name", "operator" => "equals", "value" => "Ada" }] }
    expect(query(rules).to_a).to eq([match])
  end

  it "filters across an association (roles.key)" do
    admin  = create(:user, :admin, customer: customer)
    member = create(:user, :member, customer: customer)
    rules = { "match" => "all", "conditions" => [{ "field" => "roles.key", "operator" => "equals", "value" => "admin" }] }
    result = query(rules).to_a
    expect(result).to include(admin)
    expect(result).not_to include(member)
  end

  it "never returns users from another tenant even if a condition would match" do
    create(:user, customer: other, first_name: "Ada")
    rules = { "match" => "all", "conditions" => [{ "field" => "first_name", "operator" => "equals", "value" => "Ada" }] }
    expect(query(rules).to_a).to be_empty
  end

  it "fails closed for unknown/dangerous fields instead of dropping the only restriction" do
    create(:user, customer: customer)
    rules = { "match" => "all",
              "conditions" => [{ "field" => "email\") OR 1=1 --", "operator" => "equals", "value" => "x" }] }
    expect { query(rules).to_a }.not_to raise_error
    expect(query(rules)).to be_empty
    expect(described_class.valid?(rules)).to be(false)
  end

  it "supports match=any (OR)" do
    a = create(:user, customer: customer, first_name: "Ada")
    b = create(:user, customer: customer, first_name: "Bob")
    create(:user, customer: customer, first_name: "Cy")
    rules = { "match" => "any", "conditions" => [
      { "field" => "first_name", "operator" => "equals", "value" => "Ada" },
      { "field" => "first_name", "operator" => "equals", "value" => "Bob" }
    ] }
    expect(query(rules).to_a).to contain_exactly(a, b)
  end

  it "compiles a nested group with per-join operators (AND of OR)" do
    admin     = create(:user, :admin,  customer: customer, first_name: "Ada")
    owner_ish = create(:user, :member, customer: customer, first_name: "Ada")
    bob       = create(:user, :admin,  customer: customer, first_name: "Bob")
    rules = {
      "type" => "group", "joins" => ["AND"],
      "conditions" => [
        { "field" => "first_name", "operator" => "equals", "value" => "Ada" },
        { "type" => "group", "joins" => ["OR"], "conditions" => [
          { "field" => "roles.key", "operator" => "equals", "value" => "admin" },
          { "field" => "roles.key", "operator" => "equals", "value" => "owner" }
        ] }
      ]
    }
    result = query(rules).to_a
    expect(result).to include(admin)
    expect(result).not_to include(bob)       # wrong first_name
    expect(result).not_to include(owner_ish) # member, not admin/owner
  end

  it "combines members left-associatively per the joins array ((A AND B) OR C)" do
    # first_name=Ada AND last_name=Lovelace  → ada_lovelace only
    # OR first_name=Zed                       → zed too
    ada_lovelace = create(:user, customer: customer, first_name: "Ada", last_name: "Lovelace")
    ada_other    = create(:user, customer: customer, first_name: "Ada", last_name: "Smith")
    zed          = create(:user, customer: customer, first_name: "Zed", last_name: "Zee")
    create(:user, customer: customer, first_name: "Bob", last_name: "Jones")
    rules = {
      "type" => "group", "joins" => %w[AND OR],
      "conditions" => [
        { "field" => "first_name", "operator" => "equals", "value" => "Ada" },
        { "field" => "last_name",  "operator" => "equals", "value" => "Lovelace" },
        { "field" => "first_name", "operator" => "equals", "value" => "Zed" }
      ]
    }
    result = query(rules).to_a
    expect(result).to include(ada_lovelace, zed)
    expect(result).not_to include(ada_other)
  end

  it "fails closed for an unparseable date rather than dropping the restriction" do
    create(:user, customer: customer, first_name: "Ada")
    rules = { "match" => "all", "conditions" => [
      { "field" => "created_at", "operator" => "after", "value" => "not-a-date" }
    ] }
    expect(query(rules)).to be_empty
    expect(described_class.valid?(rules)).to be(false)
  end

  it "treats empty-string as blank for string is_blank" do
    blank   = create(:user, customer: customer, unconfirmed_email: "")
    present = create(:user, customer: customer, unconfirmed_email: "new@example.com")
    rules = { "match" => "all", "conditions" => [
      { "field" => "unconfirmed_email", "operator" => "is_blank", "value" => "" }
    ] }
    result = query(rules).to_a
    expect(result).to include(blank)
    expect(result).not_to include(present)
  end

  it "preserves explicitly empty root groups as all tenant users" do
    own = create(:user, customer: customer)
    create(:user, customer: other)
    [{}, { "type" => "group", "conditions" => [], "joins" => [] },
     { "match" => "all", "conditions" => [] }].each do |rules|
      expect(described_class.valid?(rules)).to be(true)
      expect(query(rules)).to include(own)
      expect(query(rules).pluck(:customer_id).uniq).to eq([customer.id])
    end
  end

  [nil, [], "bad", { "conditions" => nil }, { "conditions" => {} }, { "conditions" => [nil] },
   { "type" => "unknown", "conditions" => [] }, { "match" => "unknown", "conditions" => [] },
   { "conditions" => [], "joins" => ["AND"] }, { "unexpected" => true }].each do |rules|
    it "fails closed for malformed tree shape #{rules.inspect}" do
      create(:user, customer: customer)
      expect { query(rules).to_a }.not_to raise_error
      expect(query(rules)).to be_empty
      expect(described_class.valid?(rules)).to be(false)
    end
  end

  it "rejects the entire tree when an invalid AND/OR member would otherwise broaden it" do
    create(:user, customer: customer, first_name: "Ada")
    valid = { "field" => "first_name", "operator" => "equals", "value" => "Ada" }
    invalid = { "field" => "created_at", "operator" => "after", "value" => "not-a-date" }
    %w[AND OR].each do |join|
      rules = { "type" => "group", "conditions" => [valid, invalid], "joins" => [join] }
      expect(query(rules)).to be_empty
    end
  end

  it "rejects unknown/missing joins and empty nested groups" do
    leaf = { "field" => "first_name", "operator" => "equals", "value" => "Ada" }
    [[], ["XOR"], [nil], "AND"].each do |joins|
      rules = { "conditions" => [leaf, leaf], "joins" => joins }
      expect(described_class.valid?(rules)).to be(false)
      expect(query(rules)).to be_empty
    end
    expect(described_class.valid?({ "conditions" => [{ "conditions" => [], "joins" => [] }] })).to be(false)
  end

  [{ "field" => "first_name", "operator" => "greater_than", "value" => "Ada" },
   { "field" => "first_name", "operator" => "unknown", "value" => "Ada" },
   { "field" => "first_name", "operator" => "equals", "value" => [] },
   { "field" => "first_name", "operator" => "is_blank", "value" => {} },
   { "field" => "id", "operator" => "equals", "value" => "0garbage" },
   { "field" => "id", "operator" => "equals", "value" => 2**64 },
   { "field" => "created_at", "operator" => "before", "value" => "2026-02-30" }].each do |leaf|
    it "rejects semantically invalid leaf #{leaf.inspect} without coercing it into a broader filter" do
      rules = { "conditions" => [leaf] }
      expect(described_class.valid?(rules)).to be(false)
      expect(query(rules)).to be_empty
    end
  end

  it "accepts typed integer and ISO date restrictions without crossing tenants" do
    own = create(:user, customer: customer)
    own.update_columns(created_at: Time.zone.parse("2026-01-01"))
    rules = { "joins" => ["AND"], "conditions" => [
      { "field" => "id", "operator" => "equals", "value" => own.id.to_s },
      { "field" => "created_at", "operator" => "after", "value" => "2025-12-31" }
    ] }
    expect(described_class.valid?(rules)).to be(true)
    expect(query(rules)).to contain_exactly(own)
  end

  it "treats LIKE metacharacters as literal values instead of audience wildcards" do
    literal = create(:user, customer: customer, first_name: "100%_match")
    create(:user, customer: customer, first_name: "100ABmatch")
    rules = { "conditions" => [{ "field" => "first_name", "operator" => "contains", "value" => "%_" }] }
    expect(query(rules)).to contain_exactly(literal)
  end

  it "bounds recursive depth, total nodes, and scalar bytes on persisted re-evaluation" do
    leaf = { "field" => "first_name", "operator" => "equals", "value" => "Ada" }
    nested = leaf
    (described_class::MAX_DEPTH + 1).times { nested = { "conditions" => [nested] } }
    expect(described_class.valid?(nested)).to be(false)
    expect(query(nested)).to be_empty

    large = { "match" => "all", "conditions" => Array.new(described_class::MAX_NODES, leaf) }
    expect(described_class.valid?(large)).to be(false)
    expect(query(large)).to be_empty

    oversized = { "conditions" => [leaf.merge("value" => "x" * (described_class::MAX_VALUE_BYTES + 1))] }
    expect(described_class.valid?(oversized)).to be(false)
    expect(query(oversized)).to be_empty
  end
end
