# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageContentGenerator::DynamicOptionsResolver do
  let_it_be(:customer) { create(:customer) }
  let(:schema) do
    [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" },
     { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }]
  end
  let(:course) { create(:entity, customer: customer, name: "Course", property_schema: schema.to_json) }

  def field(label_field)
    { "id" => "f", "html_type" => "select",
      "dynamic_options" => { "options_source" => "query", "entity_id" => course.id.to_s, "label_field" => label_field } }
  end

  def resolve(label_field)
    described_class.new(customer.id, audience: EntityAttributeAudience::ADMIN).resolve([field(label_field)]).first["options"]
  end

  it "stores the record id and labels with the display field, numbering repeats" do
    first = create(:entity_entry, customer: customer, entity: course, data: { title: "Intro" }.to_json)
    second = create(:entity_entry, customer: customer, entity: course, data: { title: "Intro" }.to_json)
    blank = create(:entity_entry, customer: customer, entity: course, data: {}.to_json)

    expect(resolve("title")).to contain_exactly(
      { "label" => "Intro (##{first.id})", "value" => first.id.to_s },
      { "label" => "Intro (##{second.id})", "value" => second.id.to_s },
      { "label" => "Untitled (##{blank.id})", "value" => blank.id.to_s }
    )
  end

  it "lists nothing for a display field that is not labelable, unknown or id" do
    create(:entity_entry, customer: customer, entity: course, data: { title: "Intro", notes: "n" }.to_json)

    expect(resolve("notes")).to eq([])
    expect(resolve("missing")).to eq([])
    expect(resolve("id")).to eq([])
  end

  describe "row scope" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:member) { create(:user, :member, customer: customer) }
    let(:peer) { create(:user, :member, customer: customer) }
    let(:other_customer) { create(:customer) }
    let(:assignment) do
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      student = create(:entity, customer: customer, name: "Student", extended_model: person_model,
                       property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      create(:entity, customer: customer, name: "Assignment", property_schema: [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
        { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true,
          "config" => { "options_source" => "entity_entries", "entity_id" => student.id.to_s, "label_field" => "name" } }
      ].to_json).tap do |entity|
        own = create(:entity_entry, customer: customer, entity: student, user: member)
        peer_entry = create(:entity_entry, customer: customer, entity: student, user: peer)
        create(:entity_entry, :with_data, customer: customer, entity: entity,
               entry_data: { "title" => "Mine", "student" => own.id.to_s })
        create(:entity_entry, :with_data, customer: customer, entity: entity,
               entry_data: { "title" => "Peer", "student" => peer_entry.id.to_s })
      end
    end

    def query_field(entity)
      { "id" => "f", "html_type" => "select",
        "dynamic_options" => { "options_source" => "query", "entity_id" => entity.id.to_s, "label_field" => "title" } }
    end

    def resolve_for(entity, audience:, viewer:)
      described_class.new(customer.id, audience: audience, viewer: viewer)
                     .resolve([query_field(entity)]).first["options"]
    end

    it "scopes a query list over an owned entity the same way as a dropdown" do
      member_options = resolve_for(assignment, audience: EntityAttributeAudience::MEMBER, viewer: member)
      expect(member_options.map { |option| option["label"] }).to eq(["Mine"])

      peer_options = resolve_for(assignment, audience: EntityAttributeAudience::MEMBER, viewer: peer)
      expect(peer_options.map { |option| option["label"] }).to eq(["Peer"])

      expect(resolve_for(assignment, audience: EntityAttributeAudience::PUBLIC, viewer: nil)).to eq([])

      admin_labels = resolve_for(assignment, audience: EntityAttributeAudience::ADMIN, viewer: nil)
                       .map { |option| option["label"] }
      expect(admin_labels).to match_array(%w[Mine Peer])
    end

    it "lists every tenant row of an open entity for member and public" do
      first = create(:entity_entry, customer: customer, entity: course, data: { title: "A" }.to_json)
      second = create(:entity_entry, customer: customer, entity: course, data: { title: "B" }.to_json)

      [EntityAttributeAudience::MEMBER, EntityAttributeAudience::PUBLIC].each do |audience|
        values = resolve_for(course, audience: audience, viewer: member).map { |option| option["value"] }
        expect(values).to match_array([first.id.to_s, second.id.to_s])
      end
    end

    it "does not list another tenant's owned rows" do
      enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)
      foreign_student = create(:entity, customer: other_customer, name: "Student", extended_model: person_model,
                              property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      foreign_assignment = create(:entity, customer: other_customer, name: "Assignment", property_schema: [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
        { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true,
          "config" => { "options_source" => "entity_entries", "entity_id" => foreign_student.id.to_s, "label_field" => "name" } }
      ].to_json)
      create(:entity_entry, :with_data, customer: other_customer, entity: foreign_assignment,
             entry_data: { "title" => "Foreign" })

      expect(resolve_for(assignment, audience: EntityAttributeAudience::MEMBER, viewer: member)
               .map { |option| option["label"] }).not_to include("Foreign")
    end
  end
end
