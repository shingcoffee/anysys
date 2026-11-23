# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::BridgeParticipants do
  let(:customer) { create(:customer) }

  include_context "student course association"

  let(:schema) { Array(bridge_entity.property_schema_json) }
  let(:source) { schema.find { |attribute| attribute["name_slug"] == "student" } }
  let(:target) { schema.find { |attribute| attribute["name_slug"] == "course" } }

  it "tells the bare declaring participant from the stored target picker and names the entity each references" do
    expect(described_class.bare?(source)).to be(true)
    expect(described_class.bare?(target)).to be(false)
    expect(described_class.participant?(schema.find { |attribute| attribute["name_slug"] == "grade" })).to be(false)
    expect(described_class.referenced_entity_id(source)).to eq(student_entity.id.to_s)
    expect(described_class.referenced_entity_id(target)).to eq(course_entity.id.to_s)
    expect(described_class.referenced_entity_id({ "name_slug" => "grade" })).to be_nil
  end

  it "turns the bare participant into a picker labelled by its entity's first labelable field, leaving the rest as stored" do
    pickers = described_class.pickers(schema, customer_id: customer.id)

    expect(pickers.first).to include("name_slug" => "student", "html_type" => "select",
                                     "config" => { "options_source" => "entity_entries", "entity_id" => student_entity.id.to_s,
                                                   "label_field" => "full_name" })
    expect(pickers.drop(1)).to eq(schema.drop(1))
    expect(Array(bridge_entity.reload.property_schema_json).first).to eq(source)
  end

  it "skips fields the admin cannot see or that cannot label a record" do
    student_entity.update!(property_schema: [
      { "name" => "Photo", "name_slug" => "photo", "html_type" => "file" },
      { "name" => "Private", "name_slug" => "private_name", "html_type" => "text",
        "visibility" => { "admin" => false, "member" => true, "public" => false } },
      { "name" => "Nickname", "name_slug" => "nickname", "html_type" => "text" }
    ].to_json)

    expect(described_class.label_field(student_entity.id, customer.id)).to eq("nickname")
  end

  it "leaves the participant bare when its entity has no labelable field or is not the tenant's" do
    student_entity.update!(property_schema: [{ "name" => "Photo", "name_slug" => "photo", "html_type" => "file" }].to_json)
    expect(described_class.pickers(schema, customer_id: customer.id).first).to eq(source)

    expect(described_class.label_field(student_entity.id, create(:customer).id)).to be_nil
  end
end
