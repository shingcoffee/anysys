# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::Serializer do
  let(:customer) { create(:customer) }

  it "echoes owner only when the stored attribute is flagged true" do
    entity = build(:entity, customer: customer, name: "Assignment", property_schema: [
      { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true },
      { "name" => "Title", "name_slug" => "title", "html_type" => "text", "owner" => false },
      { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" }
    ].to_json)
    entity.save(validate: false)

    schema = described_class.call(entity)[:property_schema]
    expect(schema[0]).to include("owner" => true)
    expect(schema[1]).not_to have_key("owner")
    expect(schema[2]).not_to have_key("owner")
  end
end
