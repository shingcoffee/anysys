# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::ReferenceDependents do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:title) { { "name" => "Title", "name_slug" => "title", "html_type" => "text" } }

  def dropdown(target, name: "Course", slug: "course", label_field: "title")
    { "name" => name, "name_slug" => slug, "html_type" => "select",
      "config" => { "options_source" => "entity_entries", "entity_id" => target.id.to_s, "label_field" => label_field } }
  end

  def form_config(target, label_field: "title", nested: false)
    field = { "id" => "f1", "label" => "Pick a course", "html_type" => "select",
              "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => target.id.to_s, "label_field" => label_field } }
    field = { "field_type" => "columns", "columns" => [{ "fields" => [field] }] } if nested
    { "metadata" => {}, "pages" => [{ "fields" => [field] }] }
  end

  describe "#references" do
    it "finds dropdowns of the tenant's other entities and skips trashed, bridge and self references" do
      course = create(:entity, customer: customer, name: "Course", property_schema: [title].to_json)
      application = create(:entity, customer: customer, name: "Application", property_schema: [dropdown(course)].to_json)
      trashed = create(:entity, customer: customer, name: "Old", property_schema: [dropdown(course, name: "Old course", slug: "old")].to_json)
      trashed.soft_delete
      create(:entity, customer: other_customer, name: "Foreign", property_schema: [title].to_json)

      refs = described_class.for_trash(course).references

      expect(refs.map { |ref| [ref.entity, ref.field_label, ref.label_field] }).to eq([[application, "Course", "title"]])
      expect(described_class.field_paths(refs)).to eq(["Application › Course"])
    end

    it "sees a shared entity's referrers in every tenant and in tenant overrides" do
      campus = Current.set(shared_resources_mode: true) { create(:entity, :shared, name: "Campus", property_schema: [title].to_json) }
      create(:entity, customer: other_customer, name: "Room", property_schema: [dropdown(campus, name: "Campus", slug: "campus")].to_json)
      event = Current.set(shared_resources_mode: true) { create(:entity, :shared, name: "Event", property_schema: [title].to_json) }
      Current.set(customer: customer) do
        Entity.find(event.id).update!(property_schema: [title, dropdown(campus, name: "Venue", slug: "venue")].to_json)
      end

      expect(described_class.for_trash(campus).references.map(&:field_label)).to contain_exactly("Campus", "Venue")
    end

    it "reports associations to the entity with their display field" do
      course = create(:entity, customer: customer, name: "Course", property_schema: [title].to_json)
      create(:entity, customer: customer, name: "Student", property_schema: [title].to_json, associations: [
        { "target_entity_id" => course.id.to_s, "target_entity_name" => "Course", "display_field" => "title", "display_field_label" => "Title" }
      ].to_json)

      expect(described_class.for_save(course).references.map(&:label_field)).to include("title")
    end
  end

  describe "#forms" do
    it "lists launched forms whose dropdown shows the field, including nested columns" do
      course = create(:entity, customer: customer, name: "Course", property_schema: [title].to_json)
      launched = create(:page, customer: customer, launched: true, entity: course,
                        configuration_json: form_config(course, nested: true))
      create(:page, customer: customer, launched: false, entity: course,
             configuration_json: form_config(course))

      forms = described_class.for_save(course).forms("title")

      expect(forms.map(&:page)).to eq([launched])
      expect(forms.first.field_label).to eq("Pick a course")
      expect(forms.first.audiences).to eq(launched.visible_audiences)
      expect(described_class.for_save(course).forms("code")).to eq([])
    end
  end
end
