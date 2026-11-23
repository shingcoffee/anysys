# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Domains::Directory do
  let(:customer) { create(:customer) }
  let(:schema) do
    [
      { "name" => "Name", "name_slug" => "name", "display_label" => "Name", "html_type" => "text", "type" => "String" },
      { "name" => "Total", "name_slug" => "total", "display_label" => "Total", "type" => "Calculated" }
    ].to_json
  end

  def call = described_class.call(customer_id: customer.id)
  def cards = call.flat_map(&:cards)

  def entry_for(entity, owner: customer, updated_at: Time.current)
    create(:entity_entry, customer: owner, entity: entity).tap { |entry| entry.update_column(:updated_at, updated_at) }
  end

  def place(entity, domain)
    EntityDomainMembership.create!(customer: customer, entity_domain: domain, entity: entity)
  end

  def ids(section) = section.cards.map { |card| card.entity.id }

  it "returns no sections when the customer has no browsable entities" do
    create(:entity, customer: customer, name: "Link", category: :bridge)
    expect(call).to eq([])
  end

  it "puts every entity in one ungrouped section when the customer has no domains" do
    alpha = create(:entity, customer: customer, name: "Alpha", display_label: "Alpha")
    sections = call
    expect(sections.size).to eq(1)
    expect(sections.first).to be_ungrouped
    expect(ids(sections.first)).to eq([alpha.id])
  end

  it "builds cards with tenant-scoped entry and page stats for associated entities too" do
    guardian = create(:entity, customer: customer, name: "Guardian", display_label: "guardians",
                      property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    student = create(:entity, customer: customer, name: "Student", display_label: "Students", property_schema: schema,
                              associations: [{ "target_entity_id" => guardian.id, "display_field" => "name", "display_field_label" => "Name" }].to_json)
    entry_for(student, updated_at: 3.days.ago)
    latest = 1.hour.ago.change(usec: 0)
    entry_for(student, updated_at: latest)
    entry_for(student, owner: create(:customer))
    create(:page, customer: customer, entity: student)

    by_id = cards.index_by { |card| card.entity.id }
    expect(by_id.keys).to contain_exactly(student.id, guardian.id)
    expect(by_id[student.id]).to have_attributes(entry_count: 2, last_entry_at: latest, form_count: 1)
    expect(by_id[guardian.id]).to have_attributes(entry_count: 0, last_entry_at: nil, form_count: 0)
  end

  it "arranges entities into domains by name, ungrouped last, totals each, and skips domains with nothing to browse" do
    student = create(:entity, customer: customer, name: "Student", display_label: "Student")
    course = create(:entity, customer: customer, name: "Course", display_label: "Course")
    order = create(:entity, customer: customer, name: "Order", display_label: "Order")
    loose = create(:entity, customer: customer, name: "Loose", display_label: "Loose")
    academics = create(:entity_domain, customer: customer, name: "Academics")
    sales = create(:entity_domain, customer: customer, name: "sales")
    create(:entity_domain, customer: customer, name: "Empty")
    [[student, academics], [course, academics], [order, sales]].each { |entity, domain| place(entity, domain) }
    entry_for(student, updated_at: 2.days.ago)
    latest = 1.hour.ago.change(usec: 0)
    entry_for(course, updated_at: latest)

    sections = call
    expect(sections.map { |section| section.domain&.name }).to eq(["Academics", "sales", nil])
    expect(sections.map(&:key)).to eq([academics.id.to_s, sales.id.to_s, "ungrouped"])
    expect(ids(sections.first)).to contain_exactly(course.id, student.id)
    expect(sections.drop(1).map { |section| ids(section) }).to eq([[order.id], [loose.id]])
    expect(sections.map(&:record_type_count)).to eq([2, 1, 1])
    expect(sections.first.entry_count).to eq(2)
    expect(sections.first.last_entry_at).to eq(latest)
    expect(sections.second.last_entry_at).to be_nil
  end

  it "keeps an ungrouped section for unbound pages once every entity sits in a domain" do
    student = create(:entity, customer: customer, name: "Student", display_label: "Student")
    place(student, create(:entity_domain, customer: customer, name: "All"))
    orphan = create(:page, customer: customer, entity: student)
    orphan.entity_id = nil
    orphan.save!(validate: false)

    other = call.last
    expect(other).to be_ungrouped
    expect(other).to have_attributes(cards: [], record_type_count: 0, form_count: 1)
  end

  it "ignores another tenant's domains and memberships" do
    shared = create(:entity, :shared, name: "SharedRoster")
    other = create(:customer)
    foreign_domain = create(:entity_domain, customer: other, name: "Foreign")
    EntityDomainMembership.create!(customer: other, entity_domain: foreign_domain, entity: shared)
    create(:entity, customer: other, name: "Foreign")

    sections = call
    expect(sections.size).to eq(1)
    expect(sections.first).to be_ungrouped
    expect(ids(sections.first)).to eq([shared.id])
  end
end
