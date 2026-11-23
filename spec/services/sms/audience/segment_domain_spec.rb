# frozen_string_literal: true

require "rails_helper"
require_relative "../audience_domain_helpers"

RSpec.describe "SMS dynamic audience compiler and services" do
  include SmsAudienceDomainHelpers
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }

  def query(rules, specs: nil)
    Sms::Audience::SegmentQuery.call(customer: customer, rules: rules, field_specs: specs)
  end

  def valid?(rules, specs: nil)
    Sms::Audience::SegmentQuery.valid?(customer: customer, rules: rules, field_specs: specs)
  end

  it "matches intentional empty roots and remains tenant-scoped" do
    contact = create(:sms_contact, customer: customer)
    create(:sms_contact)
    [{}, group].each do |rules|
      expect(valid?(rules)).to be(true)
      expect(query(rules).pluck(:id)).to eq([contact.id])
    end
  end

  it "folds mixed joins left-associatively and honors independent nested groups" do
    alice = create(:sms_contact, customer: customer, name: "Alice", status: "active", country_code: "CN")
    bob = create(:sms_contact, customer: customer, name: "Bob", status: "archived", country_code: "US")
    create(:sms_contact, customer: customer, name: "Alice", status: "archived", country_code: "CN")
    rules = group(condition("name", "Alice"), condition("status", "active"), condition("country_code", "US"), joins: %w[AND OR])
    expect(query(rules).pluck(:id)).to eq([alice.id, bob.id])
    nested = group(group(condition("name", "Bob"), condition("status", "active"), joins: ["OR"]), condition("country_code", "CN"))
    expect(query(nested).pluck(:id)).to eq([alice.id])
  end

  it "rejects any malformed subtree instead of dropping it or broadening the audience" do
    create(:sms_contact, customer: customer)
    invalid = [nil, [], "{}", { "conditions" => {} }, { "conditions" => [], "match" => "all" },
      group(group), group(condition("customer_id", customer.id)), group(condition("name", "Alice", operator: "eval")),
      group(condition("name", {})), group(condition("name", "Alice"), joins: ["AND"]),
      group(condition("name", "Alice"), condition("status", "active"), joins: ["XOR"]),
      group(condition("name", "Alice").merge("sql" => "1=1"))]
    invalid.each do |rules|
      expect(valid?(rules)).to be(false), rules.inspect
      expect(query(rules)).to be_empty
    end
  end

  it "quotes injection attempts and escapes LIKE wildcard and escape characters" do
    literal = create(:sms_contact, customer: customer, name: "50%_off\\coupon")
    create(:sms_contact, customer: customer, name: "50xxoff coupon")
    expect(query(group(condition("name", "%_", operator: "contains"))).pluck(:id)).to eq([literal.id])
    expect(query(group(condition("name", "\\", operator: "contains"))).pluck(:id)).to eq([literal.id])
    expect(query(group(condition("name", "' OR 1=1 --")))).to be_empty
    expect(valid?(group(condition("attributes.x') OR 1=1 --", "x")), specs: {})).to be(false)
  end

  it "implements all curated string operators without accepting SQL accessors" do
    named = create(:sms_contact, customer: customer, name: "Alice")
    blank = create(:sms_contact, customer: customer, name: "")
    expect(query(group(condition("name", "Alice", operator: "not_equals"))).pluck(:id)).to eq([blank.id])
    expect(query(group(condition("name", "lic", operator: "not_contains"))).pluck(:id)).to eq([blank.id])
    expect(query(group(condition("name", "", operator: "is_blank"))).pluck(:id)).to eq([blank.id])
    expect(query(group(condition("name", "", operator: "is_present"))).pluck(:id)).to eq([named.id])
    %w[credential_id customer_id source_entity.name customer.name destroy name.sql].each do |field|
      expect(valid?(group(condition(field, "x")))).to be(false)
    end
  end

  it "enforces JSON, scalar, node and depth budgets at exact boundaries" do
    expect(valid?(group(condition("name", "a" * 1024)))).to be(true)
    expect(valid?(group(condition("name", "a" * 1025)))).to be(false)
    expect(valid?(group(condition("name", { "x" => true }, operator: "is_blank")))).to be(false)
    leaves = Array.new(99) { condition("status", "active") }
    expect(valid?(group(*leaves))).to be(true)
    expect(valid?(group(*leaves, condition("status", "active")))).to be(false)
    depth = condition("name", "Alice")
    8.times { depth = group(depth) }
    expect(valid?(depth)).to be(true)
    expect(valid?(group(depth))).to be(false)
    oversized = group(*Array.new(40) { condition("name", "x" * 1024) })
    expect(valid?(oversized)).to be(false)
  end

  it "strictly parses ISO datetimes with explicit offsets" do
    contact = create(:sms_contact, customer: customer, created_at: Time.utc(2026, 10, 12))
    expect(query(group(condition("created_at", "2026-10-13T00:00:00+08:00", operator: "before"))).pluck(:id)).to eq([contact.id])
    expect(query(group(condition("created_at", "2026-10-11T00:00:00Z", operator: "after"))).pluck(:id)).to eq([contact.id])
    %w[2026-10-13 2026-10-13T00:00:00 2026-02-30T00:00:00Z].each do |value|
      expect(valid?(group(condition("created_at", value, operator: "after")))).to be(false)
    end
    expect(valid?(group(condition("created_at", "", operator: "is_present")))).to be(true)
  end

  it "catalogs actual tenant scalar types, combines integer/float, and omits mixed and null-only fields" do
    create(:sms_contact, customer: customer, custom_attributes: { "city" => "Paris", "score" => 1, "vip" => true, "mixed" => 1, "nil_only" => nil })
    create(:sms_contact, customer: customer, custom_attributes: { "city" => nil, "score" => 2.5, "vip" => false, "mixed" => "one" })
    create(:sms_contact, custom_attributes: { "foreign" => "secret" })
    catalog = Sms::Audience::FieldCatalog.new(customer: customer)
    expect(catalog.custom_specs).to eq("attributes.city" => "string", "attributes.score" => "float", "attributes.vip" => "boolean")
    expect(catalog.resolve("attributes.score")[:type]).to eq(:float)
    expect(catalog.resolve("attributes.foreign")).to be_nil
    expect(catalog.fields.all? { |field| field.keys.sort == %i[field label operators type] }).to be(true)
  end

  it "returns at most 128 sorted valid custom keys without loading tenant contacts" do
    at = Time.current
    rows = 140.times.map do |index|
      { customer_id: customer.id, phone_e164: "+86139#{format('%08d', index)}", created_at: at, updated_at: at,
        custom_attributes: { format("field_%03d", index) => index, "Bad-Key" => "omit" } }
    end
    Sms::Contact.insert_all!(rows)
    catalog = Sms::Audience::FieldCatalog.new(customer: customer)
    expect(Sms::Contact).not_to receive(:find_each)
    expect(catalog.custom_specs.size).to eq(128)
    expect(catalog.custom_specs.keys.first).to eq("attributes.field_000")
    expect(catalog.custom_specs.keys.last).to eq("attributes.field_127")
  end

  it "uses frozen types even when the live catalog changes and excludes missing/wrong-type JSON values" do
    number = create(:sms_contact, customer: customer, custom_attributes: { "score" => 1 })
    text = create(:sms_contact, customer: customer, custom_attributes: { "score" => "1" })
    create(:sms_contact, customer: customer, custom_attributes: {})
    rules = group(condition("attributes.score", "1"))
    expect(query(rules)).to be_empty
    expect(query(rules, specs: { "attributes.score" => "float" }).pluck(:id)).to eq([number.id])
    expect(query(rules, specs: { "attributes.score" => "string" }).pluck(:id)).to eq([text.id])
    expect(query(group(condition("attributes.score", 9, operator: "not_equals")), specs: { "attributes.score" => "float" }).pluck(:id)).to eq([number.id])
  end

  it "strictly casts numbers and booleans while respecting JSON type guards" do
    vip = create(:sms_contact, customer: customer, custom_attributes: { "vip" => true, "score" => 2.5 })
    ordinary = create(:sms_contact, customer: customer, custom_attributes: { "vip" => false, "score" => 1 })
    expect(query(group(condition("attributes.vip", "true"))).pluck(:id)).to eq([vip.id])
    expect(query(group(condition("attributes.vip", false))).pluck(:id)).to eq([ordinary.id])
    expect(query(group(condition("attributes.vip", true, operator: "not_equals"))).pluck(:id)).to eq([ordinary.id])
    expect(query(group(condition("attributes.score", "2", operator: "greater_than"))).pluck(:id)).to eq([vip.id])
    expect(query(group(condition("attributes.score", 2, operator: "less_than"))).pluck(:id)).to eq([ordinary.id])
    ["yes", "1", 1, nil].each { |value| expect(valid?(group(condition("attributes.vip", value)))).to be(false) }
    ["NaN", "Infinity", "1x", true, nil].each { |value| expect(valid?(group(condition("attributes.score", value)))).to be(false) }
    expect(valid?(rules = group(condition("attributes.score", 1)), specs: { "attributes.score" => "integer" })).to be(false)
    expect(valid?(rules, specs: { "name" => "string" })).to be(false)
  end

  it "saves a valid dynamic segment and fences stale or foreign updates" do
    result = Sms::Audience::SaveSegment.call(customer: customer, actor: actor, attributes: { name: "CN contacts", segment_rules: group(condition("country_code", "CN")) })
    expect(result).to be_success
    record = result.value
    changed = Sms::Audience::SaveSegment.call(customer: customer, actor: actor, segment: record, attributes: { name: "Updated", lock_version: 0 })
    expect(changed).to be_success
    expect(Sms::Audience::SaveSegment.call(customer: customer, actor: actor, segment: record, attributes: { name: "Lost", lock_version: 0 }).code).to eq(:stale_edit)
    expect(Sms::Audience::SaveSegment.call(customer: customer, actor: actor, segment: create(:sms_segment), attributes: {}).code).to eq(:not_found)
  end

  it "rejects malformed segment saves/previews and protected save attributes without writes" do
    [group(group), []].each do |rules|
      expect(Sms::Audience::SaveSegment.call(customer: customer, actor: actor, attributes: { name: "Bad", segment_rules: rules })).not_to be_success
      expect(Sms::Audience::Preview.call(customer: customer, rules: rules).code).to eq(:invalid_rules)
    end
    expect(Sms::Audience::SaveSegment.call(customer: customer, actor: actor, attributes: { name: "X", customer_id: customer.id }).code).to eq(:invalid_input)
    expect(Sms::Audience::Segment.count).to eq(0)
  end

  it "separates matched membership from permission with a side-effect-free bounded preview" do
    create(:sms_contact, :granted, customer: customer)
    create(:sms_contact, customer: customer)
    create(:sms_contact, :archived, :granted, customer: customer)
    opted = create(:sms_contact, :granted, customer: customer)
    Sms::OptOut.record_global!(phone_e164: opted.phone_e164, reason: "STOP")
    before = [Sms::Contact.count, Sms::ConsentEvent.count, Sms::Message.count, Sms::CampaignRecipient.count, Sms::OptOut.count]
    clear_enqueued_jobs
    at = Time.current
    result = Sms::Audience::Preview.call(customer: customer, rules: {}, at: at)
    expect(result).to be_success
    expect(result.value).to include(matched_count: 4, eligible_count: 1,
      excluded_counts: { consent_missing: 1, contact_archived: 1, opted_out: 1 }, evaluated_at: at)
    expect(result.value[:samples].size).to eq(4)
    expect(result.value[:samples].all? { |sample| sample.keys.sort == %i[contact_id name phone_e164 consent_status eligible reason].sort }).to be(true)
    expect([Sms::Contact.count, Sms::ConsentEvent.count, Sms::Message.count, Sms::CampaignRecipient.count, Sms::OptOut.count]).to eq(before)
    expect(enqueued_jobs).to be_empty
  end

  it "limits samples to five and rejects oversized audiences before streaming" do
    at = Time.current
    Sms::Contact.insert_all!(10_001.times.map do |index|
      { customer_id: customer.id, phone_e164: "+86137#{format('%08d', index)}", created_at: at, updated_at: at }
    end)
    expect(Sms::Audience::Preview.call(customer: customer, rules: {}).code).to eq(:audience_too_large)
    Sms::Contact.where(id: Sms::Contact.maximum(:id)).delete_all
    result = Sms::Audience::Preview.call(customer: customer, rules: {})
    expect(result.value[:matched_count]).to eq(10_000)
    expect(result.value[:samples].size).to eq(5)
  end
end
