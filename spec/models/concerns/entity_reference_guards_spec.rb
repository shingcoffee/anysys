# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entity reference guards" do
  let_it_be(:customer) { create(:customer) }
  let(:title) { { "name" => "Title", "name_slug" => "title", "html_type" => "text" } }
  let!(:course) { create(:entity, customer: customer, name: "Course", property_schema: [title].to_json) }

  def dropdown(target)
    { "name" => "Course", "name_slug" => "course", "html_type" => "select",
      "config" => { "options_source" => "entity_entries", "entity_id" => target.id.to_s, "label_field" => "title" } }
  end

  describe "trash" do
    it "refuses to trash an entity other entities reference, naming the fields" do
      create(:entity, customer: customer, name: "Application", property_schema: [dropdown(course)].to_json)

      expect(course.soft_delete).to be(false)
      expect(course.errors[:base]).to include(
        I18n.t("maint_core.errors.validations.entity_referenced", fields: "Application › Course")
      )
      expect(Entity.find(course.id)).to be_present
    end

    it "trashes an entity nothing references" do
      expect(course.soft_delete).to be_truthy
    end
  end

  describe "saving a display field" do
    before { create(:entity, customer: customer, name: "Application", property_schema: [dropdown(course)].to_json) }

    it "refuses to retype or delete a display field others use" do
      course.property_schema = [title.merge("html_type" => "textarea")].to_json
      expect(course.save).to be(false)
      expect(course.errors[:property_schema]).to include(
        I18n.t("maint_core.errors.validations.display_field_in_use", label: "Title", fields: "Application › Course")
      )

      fresh = Entity.find(course.id)
      fresh.property_schema = [].to_json
      expect(fresh.save).to be(false)
    end

    it "refuses to hide a display field from an audience of a launched form that lists it" do
      page = create(:page, customer: customer, launched: true, name: "Apply", entity: course,
                    configuration_json: { "metadata" => {}, "pages" => [{ "fields" => [
                      { "id" => "f1", "label" => "Course", "html_type" => "select",
                        "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title" } }
                    ] }] })
      audience = page.visible_audiences.first

      fresh = Entity.find(course.id)
      fresh.property_schema = [title.merge("visibility" => { audience => false })].to_json

      expect(fresh.save).to be(false)
      expect(fresh.errors[:property_schema]).to include(
        I18n.t("maint_core.errors.validations.display_field_hidden_from_form",
               label: "Title", audience: I18n.t("common.visibility.#{audience}"), form: "Apply", field: "Course")
      )
    end

    it "allows unrelated edits" do
      fresh = Entity.find(course.id)
      fresh.property_schema = [title, { "name" => "Code", "name_slug" => "code", "html_type" => "text" }].to_json

      expect(fresh.save).to be(true)
    end
  end
end
