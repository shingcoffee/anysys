# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDomains::Layout do
  let(:customer) { create(:customer) }

  include_context "student course association"

  let!(:customer_entity) { create(:entity, customer: customer, name: "customer") }
  let!(:shared_entity) { create(:entity, :shared, name: "Country") }
  let(:academics) { create(:entity_domain, customer: customer, name: "Academics") }
  let(:commerce) { create(:entity_domain, customer: customer, name: "Commerce") }

  def place(entity, domain)
    EntityDomainMembership.create!(customer: customer, entity_domain: domain, entity: entity)
  end

  def layout(query: nil, kind: nil)
    entities = Entity.where(customer_id: [customer.id, nil]).by_name.to_a
    described_class.call(customer_id: customer.id, entities: entities, query: query, kind: kind)
  end

  def names(section) = section.items.map { |item| item.entity.name }

  it "orders domains by name and puts ungrouped entities last" do
    place(customer_entity, commerce)
    place(student_entity, academics)

    sections = layout
    expect(sections.map { |section| section.domain&.name }).to eq(["Academics", "Commerce", nil])
    expect(names(sections.last)).to include("Course", "Country", "assoc_student_course")
    expect(sections.last).to be_ungrouped
  end

  it "places a bridge only where it is explicitly placed" do
    place(student_entity, academics)
    place(course_entity, academics)

    expect(layout.find { |s| s.domain == academics }.items.map(&:entity)).to contain_exactly(student_entity, course_entity)
    expect(names(layout.find(&:ungrouped?))).to include("assoc_student_course")

    place(bridge_entity, commerce)
    expect(layout.find { |s| s.domain == commerce }.items.map(&:entity)).to eq([bridge_entity])
  end

  it "places shared entities per customer without touching the shared row" do
    place(shared_entity, commerce)

    expect(names(layout.find { |s| s.domain == commerce })).to eq(["Country"])
    expect(shared_entity.reload.customer_id).to be_nil
  end

  it "ignores another customer's domains and memberships" do
    other = create(:customer)
    other_domain = create(:entity_domain, customer: other, name: "Foreign")
    EntityDomainMembership.create!(customer: other, entity_domain: other_domain, entity: shared_entity)

    sections = layout
    expect(sections.map(&:domain)).not_to include(other_domain)
    expect(names(sections.find(&:ungrouped?))).to include("Country")
  end

  it "keeps empty domains unless a search is active, and filters by label or name" do
    academics
    place(customer_entity, commerce)

    expect(layout.map { |s| s.domain&.name }).to include("Academics")
    searched = layout(query: "CUSTOM")
    expect(searched.map { |s| s.domain&.name }).to eq(["Commerce"])
    expect(names(searched.first)).to eq(["customer"])
  end

  it "filters by kind and drops empty domains while filtering" do
    academics
    place(customer_entity, commerce)

    bridges = layout(kind: "bridge")
    expect(bridges.flat_map { |s| names(s) }).to eq(["assoc_student_course"])
    expect(bridges.map(&:domain)).to all(be_nil)

    plain = layout(kind: "entity").flat_map { |s| names(s) }
    expect(plain).to include("customer", "Country")
    expect(plain).not_to include("assoc_student_course")
  end

  it "ignores an unknown kind" do
    expect(layout(kind: "bogus").flat_map { |s| names(s) }).to include("assoc_student_course", "customer")
  end
end
