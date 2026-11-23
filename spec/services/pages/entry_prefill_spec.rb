# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::EntryPrefill do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
      { "name" => "Notes", "name_slug" => "notes", "html_type" => "textarea" },
      { "name" => "Secret", "name_slug" => "secret", "html_type" => "text",
        "visibility" => { "admin" => false, "member" => true, "public" => false } }
    ].to_json)
  end
  let(:page) do
    fields = %w[title notes secret].map { |slug| { "id" => "f_#{slug}", "property_slug" => slug, "source" => "entity" } }
    fields << { "id" => "f_email", "property_slug" => "email", "source" => "base_model" }
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: entity, configuration: {
        metadata: { entity_id: entity.id, entity_name: entity.name },
        pages: [{ "id" => "page_1", "fields" => fields }]
      }.to_json)
    end
  end
  let(:entry) do
    create(:entity_entry, :with_data, customer: customer, entity: entity,
                                      entry_data: { "title" => "Stored", "secret" => "hidden" })
  end

  it "keys every primary field the audience sees by slug with the stored value, blanks included" do
    values = described_class.values(page: page, entry: entry, audience: EntityAttributeAudience::ADMIN)

    expect(values).to eq("title" => "Stored", "notes" => nil)
  end

  it "follows the audience's visibility" do
    values = described_class.values(page: page, entry: entry, audience: EntityAttributeAudience::MEMBER)

    expect(values).to include("secret" => "hidden")
  end

  context "with a file field" do
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
        { "name" => "Notes", "name_slug" => "notes", "html_type" => "file", "config" => { "multiple" => true } }
      ].to_json)
    end

    it "lists the filenames the entry holds" do
      record = EntityEntry.build_for(entity).create!(customer_id: customer.id, title: "Stored",
                                                     notes: [{ io: StringIO.new("a"), filename: "a.txt" }])

      values = described_class.values(page: page, entry: EntityEntry.find(record.id), audience: EntityAttributeAudience::ADMIN)

      expect(values).to eq("title" => "Stored", "notes" => ["a.txt"])
    end
  end
end
