# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::ReferenceOptions do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:admin_only) { { "admin" => true, "member" => false, "public" => false } }
  let(:schema) do
    [
      { "name" => "Code", "name_slug" => "code", "html_type" => "text" },
      { "name" => "Bio", "name_slug" => "bio", "html_type" => "textarea" },
      { "name" => "Phone", "name_slug" => "phone", "html_type" => "tel", "visibility" => admin_only }
    ]
  end
  let(:student) { create(:entity, customer: customer, name: "Student", property_schema: schema.to_json) }

  # Ruby 3.2 treats `entry("code" => "A")` as keywords, not a positional hash,
  # so `**fields` absorbs that data while `owner:` / `entity:` stay real options.
  def entry(data = nil, owner: customer, entity: student, **fields)
    create(:entity_entry, customer: owner, entity: entity, data: (data || fields).to_json)
  end

  def options(**overrides)
    described_class.call(entity_id: student.id, label_field: "code", customer_id: customer.id,
                         audience: EntityAttributeAudience::PUBLIC, **overrides)
  end

  it "lists [label, id] pairs ordered by label, case-insensitively, then by id" do
    beta = entry("code" => "beta")
    alpha = entry("code" => "Alpha")
    blank = entry("code" => "  ")

    expect(options).to eq([
      ["Untitled (##{blank.id})", blank.id.to_s],
      ["Alpha", alpha.id.to_s],
      ["beta", beta.id.to_s]
    ])
  end

  it "numbers labels that repeat and leaves unique ones alone" do
    first = entry("code" => "001")
    other = entry("code" => "002")
    second = entry("code" => "001")

    expect(options).to eq([
      ["001 (##{first.id})", first.id.to_s],
      ["001 (##{second.id})", second.id.to_s],
      ["002", other.id.to_s]
    ])
  end

  it "lists only the tenant's records" do
    mine = entry("code" => "A")
    entry({ "code" => "B" }, owner: other_customer)

    expect(options.map(&:last)).to eq([mine.id.to_s])
  end

  it "lists nothing when the display field is hidden, not labelable, unknown, id or not a slug" do
    entry("code" => "A", "bio" => "x", "phone" => "555")

    expect(options(label_field: "phone")).to eq([])
    expect(options(label_field: "phone", audience: EntityAttributeAudience::ADMIN).size).to eq(1)
    expect(options(label_field: "bio", audience: EntityAttributeAudience::ADMIN)).to eq([])
    expect(options(label_field: "nope")).to eq([])
    expect(options(label_field: "id")).to eq([])
    expect(options(label_field: "code\"; DROP")).to eq([])
  end

  it "lists nothing for a foreign, bridge, trashed or malformed target" do
    foreign = create(:entity, customer: other_customer, property_schema: schema.to_json)
    bridge = create(:entity, customer: customer, category: :bridge, property_schema: schema.to_json)
    entry("code" => "A")

    expect(options(entity_id: foreign.id)).to eq([])
    expect(options(entity_id: bridge.id)).to eq([])
    expect(options(entity_id: "abc")).to eq([])
    expect(options(customer_id: nil)).to eq([])

    student.soft_delete
    expect(options).to eq([])
  end

  it "reads a shared target's display field through the tenant's override" do
    shared = Current.set(shared_resources_mode: true) { create(:entity, :shared, name: "Campus", property_schema: schema.to_json) }
    hidden = schema.map { |attr| attr["name_slug"] == "code" ? attr.merge("visibility" => admin_only) : attr }
    Current.set(customer: customer) { Entity.find(shared.id).update!(property_schema: hidden.to_json) }
    entry({ "code" => "North" }, entity: shared)
    entry({ "code" => "South" }, owner: other_customer, entity: shared)

    expect(options(entity_id: shared.id)).to eq([])
    expect(options(entity_id: shared.id, customer_id: other_customer.id).map(&:first)).to eq(["South"])
  end

  it "caps the list at the limit" do
    3.times { |index| entry("code" => "C#{index}") }

    expect(options(limit: 2).size).to eq(2)
  end

  describe "#usable? and #label_taken?" do
    let(:source) do
      described_class.new(entity_id: student.id, label_field: "code", customer_id: customer.id,
                          audience: EntityAttributeAudience::ADMIN)
    end

    it "says whether the display field can label choices" do
      expect(source).to be_usable
      expect(source.target).to eq(student)
      expect(described_class.new(entity_id: student.id, label_field: "bio", customer_id: customer.id,
                                 audience: EntityAttributeAudience::ADMIN)).not_to be_usable
    end

    it "says whether another record already shows a label" do
      taken = entry("code" => "001")

      expect(source.label_taken?(" 001 ", except_id: 0)).to be(true)
      expect(source.label_taken?("001", except_id: taken.id)).to be(false)
      expect(source.label_taken?("", except_id: 0)).to be(false)
    end
  end

  describe "#labels" do
    def source(audience: EntityAttributeAudience::PUBLIC, label_field: "code")
      described_class.new(entity_id: student.id, label_field: label_field, customer_id: customer.id, audience: audience)
    end

    it "maps the given ids of the tenant's records to their raw labels" do
      ada = entry("code" => "Ada")
      untitled = entry({})
      foreign = entry({ "code" => "X" }, owner: other_customer)

      expect(source.labels([ada.id, untitled.id.to_s, foreign.id, "abc", ""])).to eq(ada.id.to_s => "Ada", untitled.id.to_s => nil)
      expect(source.labels([])).to eq({})
    end

    it "is nil when the display field can't label for the audience" do
      expect(source(label_field: "phone").labels([1])).to be_nil
      expect(source(label_field: "bio", audience: EntityAttributeAudience::ADMIN).labels([1])).to be_nil
    end
  end

  describe "row scope" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:member) { create(:user, :member, customer: customer) }
    let(:peer) { create(:user, :member, customer: customer) }
    let(:foreign_member) { create(:user, :member, customer: other_customer) }
    let(:admin) { create(:user, :admin, customer: customer) }

    let(:person) do
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      create(:entity, customer: customer, name: "Learner", extended_model: person_model, property_schema: schema.to_json)
    end
    let!(:own_person) { create(:entity_entry, customer: customer, entity: person, user: member, data: { "code" => "Mine" }.to_json) }
    let!(:peer_person) { create(:entity_entry, customer: customer, entity: person, user: peer, data: { "code" => "Peer" }.to_json) }
    let!(:foreign_person_entity) do
      enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)
      create(:entity, customer: other_customer, name: "Learner", extended_model: person_model, property_schema: schema.to_json)
    end
    let!(:foreign_person) do
      create(:entity_entry, customer: other_customer, entity: foreign_person_entity, user: foreign_member,
             data: { "code" => "Foreign" }.to_json)
    end

    def scoped_options(audience:, viewer: nil, entity_id: person.id, customer_id: customer.id)
      described_class.call(entity_id: entity_id, label_field: "code", customer_id: customer_id,
                           audience: audience, viewer: viewer)
    end

    it "lists only the member's own person row and never a peer's or another tenant's" do
      values = scoped_options(audience: EntityAttributeAudience::MEMBER, viewer: member).map(&:last)

      expect(values).to eq([own_person.id.to_s])
      expect(values).not_to include(peer_person.id.to_s, foreign_person.id.to_s)
    end

    it "lists every tenant person row for an admin and still excludes other tenants" do
      values = scoped_options(audience: EntityAttributeAudience::ADMIN, viewer: admin).map(&:last)

      expect(values).to match_array([own_person.id.to_s, peer_person.id.to_s])
      expect(values).not_to include(foreign_person.id.to_s)
    end

    it "lists no person rows to the public, and every tenant row for an open entity" do
      expect(scoped_options(audience: EntityAttributeAudience::PUBLIC, viewer: nil)).to eq([])

      open_mine = entry("code" => "OpenA")
      open_peer = entry("code" => "OpenB")
      values = described_class.call(entity_id: student.id, label_field: "code", customer_id: customer.id,
                                    audience: EntityAttributeAudience::PUBLIC, viewer: nil).map(&:last)

      expect(values).to match_array([open_mine.id.to_s, open_peer.id.to_s])
    end

    it "fails closed for a member with no viewer or a viewer from another tenant" do
      expect(scoped_options(audience: EntityAttributeAudience::MEMBER, viewer: nil)).to eq([])
      expect(scoped_options(audience: EntityAttributeAudience::MEMBER, viewer: foreign_member)).to eq([])
    end

    it "labels only in-scope ids for a member" do
      source = described_class.new(entity_id: person.id, label_field: "code", customer_id: customer.id,
                                   audience: EntityAttributeAudience::MEMBER, viewer: member)

      expect(source.labels([own_person.id, peer_person.id, foreign_person.id]))
        .to eq(own_person.id.to_s => "Mine")
    end
  end
end
