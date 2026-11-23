# frozen_string_literal: true

# Launched pages for the "student course association" journey specs: a
# Student create page (`student_new`), the bridge page that adds the
# student's courses (`student_add_course`, student locked in), a Course
# create page (`course_new`) and an enrolment bridge page that locks both the
# student and the course (`enrolment_new`).
module JourneyPageHelpers
  def journey_reference_field(slug, entity, label_field)
    { "id" => "f_#{slug}", "property_slug" => slug, "source" => "entity", "label" => slug.humanize, "html_type" => "select",
      "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => entity.id.to_s, "label_field" => label_field } }
  end

  def journey_text_field(slug)
    { "id" => "f_#{slug}", "property_slug" => slug, "source" => "entity", "label" => slug.humanize, "html_type" => "text" }
  end

  def journey_page(entity, action_key:, fields:, form_settings: {}, **attributes)
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: entity, launched: true, action_key: action_key, **attributes,
                    configuration: {
                      form_settings: form_settings,
                      metadata: { entity_id: entity.id, entity_name: entity.name },
                      pages: [{ "id" => "page_1", "fields" => fields }]
                    }.to_json)
    end
  end

  def student_journey_page(**attributes)
    journey_page(student_entity, action_key: "student_new", fields: [journey_text_field("full_name")],
                                 form_settings: { modes: %w[create update] }, **attributes)
  end

  def course_journey_page(**attributes)
    journey_page(bridge_entity, action_key: "student_add_course",
                                fields: [journey_reference_field("student", student_entity, "full_name"),
                                         journey_reference_field("course", course_entity, "code"), journey_text_field("status")],
                                form_settings: { modes: ["create"], inputs: [{ field: "student", entity_id: student_entity.id }] },
                                name: "Add Course for Student", **attributes)
  end

  def course_create_journey_page(**attributes)
    journey_page(course_entity, action_key: "course_new", fields: [journey_text_field("code")],
                                form_settings: { modes: ["create"] }, name: "New Course", **attributes)
  end

  def enrolment_journey_page(**attributes)
    journey_page(bridge_entity, action_key: "enrolment_new",
                                fields: [journey_reference_field("student", student_entity, "full_name"),
                                         journey_reference_field("course", course_entity, "code"), journey_text_field("status")],
                                form_settings: { modes: ["create"],
                                                 inputs: [{ field: "student", entity_id: student_entity.id },
                                                          { field: "course", entity_id: course_entity.id }] },
                                name: "Enrol student in course", **attributes)
  end
end

RSpec.configure { |config| config.include JourneyPageHelpers, type: :request }
