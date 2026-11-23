# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::LaunchChecks do
  include JourneyPageHelpers

  let(:customer) { create(:customer) }
  include_context "student course association"

  let(:journey) { create(:journey, customer: customer) }

  def errors = described_class.new(journey).errors
  def message(key, **vars) = I18n.t("journeys.launch.errors.#{key}", **vars)

  context "with a launched page for every step" do
    before do
      student_journey_page
      course_journey_page
    end

    it "passes when every step has a launched page for every audience and inputs line up" do
      expect(errors).to eq([])
    end

    it "resolves each step's page once per audience" do
      allow(Pages::ActionResolver).to receive(:page_for).and_call_original
      errors
      expect(Pages::ActionResolver).to have_received(:page_for).twice
    end

    it "names a step with no launched page for an audience" do
      journey.update!(visible_audiences: %w[admin member])

      expect(errors.first).to eq(message(:page_missing, step: "start", audience: I18n.t("journeys.audiences.member")))
    end

    it "refuses a second launched journey on the same first page and audience" do
      other = create(:journey, :launched, customer: customer, name: "Enrolment")

      expect(errors).to eq([message(:start_taken, name: other.name)])
    end

    it "ignores launched journeys of other tenants and for other audiences" do
      create(:journey, :launched)
      create(:journey, :launched, customer: customer, audience_admin: false, audience_public: true)

      expect(errors).to eq([])
    end
  end

  it "flags a relate page without a locked input" do
    student_journey_page
    journey_page(bridge_entity, action_key: "student_add_course",
                                fields: [journey_reference_field("student", student_entity, "full_name")],
                                form_settings: { modes: ["create"] })

    expect(errors).to eq([message(:input_undeclared, step: "relate_1")])
  end

  it "flags an input that expects another entity" do
    journey_page(course_entity, action_key: "student_new", fields: [journey_text_field("code")],
                                form_settings: { modes: ["create"] })
    course_journey_page

    expect(errors).to eq([message(:input_entity_mismatch, step: "relate_1")])
  end

  it "flags a first page that does not create records" do
    journey_page(student_entity, action_key: "student_new", fields: [journey_text_field("full_name")],
                                 form_settings: { modes: ["update"] })
    course_journey_page

    expect(errors).to eq([message(:start_not_create, step: "start", audience: I18n.t("journeys.audiences.admin"))])
  end

  it "flags a later page that does not create records" do
    student_journey_page
    journey_page(bridge_entity, action_key: "student_add_course",
                                fields: [journey_reference_field("student", student_entity, "full_name")],
                                form_settings: { modes: ["update"], inputs: [{ field: "student", entity_id: student_entity.id }] })

    expect(errors).to eq([message(:step_not_create, step: "relate_1", audience: I18n.t("journeys.audiences.admin"))])
  end

  it "flags a locked input on the first page that no earlier step can fill" do
    student_entity.property_schema_json = Array(student_entity.property_schema_json) + [{
      "name" => "Advisor", "name_slug" => "advisor", "type" => "EntityReference", "html_type" => "select",
      "entity_id" => student_entity.id.to_s
    }]
    student_entity.save!
    journey_page(student_entity, action_key: "student_new",
                                 fields: [journey_text_field("full_name"),
                                          journey_reference_field("advisor", student_entity, "full_name")],
                                 form_settings: { modes: ["create"], inputs: [{ field: "advisor", entity_id: student_entity.id }] })
    course_journey_page

    expect(errors).to include(message(:input_unbound, step: "start", audience: I18n.t("journeys.audiences.admin"),
                                                       field: "Advisor"))
  end

  it "flags a locked input the step does not fill, using the field name" do
    student_journey_page
    journey_page(bridge_entity, action_key: "student_add_course",
                                fields: [journey_reference_field("student", student_entity, "full_name"),
                                         journey_reference_field("course", course_entity, "code")],
                                form_settings: { modes: ["create"],
                                                 inputs: [{ field: "student", entity_id: student_entity.id },
                                                          { field: "course", entity_id: course_entity.id }] })

    expect(errors).to eq([message(:input_unbound, step: "relate_1", audience: I18n.t("journeys.audiences.admin"),
                                                  field: "Course")])
  end

  it "passes a relate step that fills every locked input" do
    student_journey_page
    journey_page(course_entity, action_key: "course_new", fields: [journey_text_field("code")],
                                form_settings: { modes: ["create"] })
    journey_page(bridge_entity, action_key: "student_add_course",
                                fields: [journey_reference_field("student", student_entity, "full_name"),
                                         journey_reference_field("course", course_entity, "code")],
                                form_settings: { modes: ["create"],
                                                 inputs: [{ field: "student", entity_id: student_entity.id },
                                                          { field: "course", entity_id: course_entity.id }] })
    journey.update!(definition: {
      "steps" => [
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "course", "kind" => "create", "action_key" => "course_new" },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course",
          "inputs" => { "student" => "start", "course" => "course" } },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
      ]
    }.to_json)

    expect(errors).to eq([])
  end

  it "flags a step page that hands off to a module, since the run can't follow it" do
    page = journey_page(student_entity, action_key: "student_new", fields: [journey_text_field("full_name")],
                                       form_settings: { modes: ["create"] })
    bind_page_flowchart(page, steps: [{
      "action" => "hand_off_to_module",
      "config" => { "moduleKey" => "demo", "input" => [] }
    }])
    course_journey_page

    expect(errors).to eq([message(:step_hands_off, step: "start", audience: I18n.t("journeys.audiences.admin"))])
  end

  it "lets the last page step hand off, since its submit finishes the run, unless it repeats" do
    student_journey_page
    bind_page_flowchart(course_journey_page, steps: [{
      "action" => "hand_off_to_module",
      "config" => { "moduleKey" => "demo", "input" => [] }
    }])

    expect(errors).to eq([message(:step_hands_off, step: "relate_1", audience: I18n.t("journeys.audiences.admin"))])

    steps = journey.definition_json["steps"].map { |step| step.except("repeat") }
    journey.update!(definition: { "steps" => steps }.to_json)
    expect(described_class.new(journey.reload).errors).to eq([])
  end

  context "when the journey starts from an existing record" do
    let(:record_definition) do
      { "steps" => [
        { "key" => "record", "kind" => "record", "entity_id" => student_entity.id.to_s },
        { "key" => "courses", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "record" } },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "record" } }
      ] }.to_json
    end
    let(:journey) { create(:journey, customer: customer, name: "Add courses", definition: record_definition) }

    before { course_journey_page }

    it "passes when the first page fills its locked input from the start record" do
      expect(errors).to eq([])
    end

    it "is for admins only or for members only" do
      journey.update!(visible_audiences: %w[admin member])
      expect(errors).to include(message(:record_start_audience))

      journey.update!(visible_audiences: %w[public])
      expect(described_class.new(journey).errors).to include(message(:record_start_audience))
    end

    it "lets members start it only from a record type a member owns" do
      journey.update!(visible_audiences: %w[member])
      expect(errors).to include(message(:record_start_not_owned))
      expect(errors).not_to include(message(:record_start_audience))

      allow(People::Ownership).to receive(:kind).and_call_original
      allow(People::Ownership).to receive(:kind).with(student_entity).and_return(:owned)
      expect(described_class.new(journey).errors).not_to include(message(:record_start_not_owned))
    end

    it "needs the field its start condition reads to still be on the record type" do
      condition = ->(field) { record_definition.sub(%("kind":"record",), %("kind":"record","when":{"field":"#{field}","in":["Ada"]},)) }

      journey.update!(definition: condition.call("full_name"))
      expect(errors).to eq([])

      journey.update!(definition: condition.call("nickname"))
      expect(described_class.new(journey).errors).to eq([message(:record_when_field_missing)])
    end

    context "with a step that edits the start record" do
      let(:record_definition) do
        { "steps" => [
          { "key" => "record", "kind" => "record", "entity_id" => student_entity.id.to_s },
          { "key" => "review", "kind" => "update", "action_key" => "student_new", "record" => "record" },
          { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "record" } }
        ] }.to_json
      end
      let(:admin_label) { I18n.t("journeys.audiences.admin") }

      it "passes when the step's page edits the start record's type" do
        student_journey_page

        expect(errors).to eq([])
      end

      it "flags a page that doesn't edit records" do
        journey_page(student_entity, action_key: "student_new", fields: [journey_text_field("full_name")],
                                     form_settings: { modes: ["create"] })

        expect(errors).to eq([message(:step_not_update, step: "review", audience: admin_label)])
      end

      it "flags a page that edits another record type" do
        journey_page(course_entity, action_key: "student_new", fields: [journey_text_field("code")],
                                    form_settings: { modes: ["update"] })

        expect(errors).to eq([message(:update_entity_mismatch, step: "review", audience: admin_label)])
      end
    end

    it "needs the start record type to still be available" do
      student_entity.update_columns(status: Entity.statuses[:inactive])

      expect(errors).to include(message(:record_entity_missing))
    end

    it "flags a start record of another type than the page's locked input" do
      journey.update!(definition: record_definition.sub(%("entity_id":"#{student_entity.id}"), %("entity_id":"#{course_entity.id}")))

      expect(errors).to eq([message(:input_entity_mismatch, step: "courses")])
    end

    it "refuses a second live journey from the same record type and first page, but not from another page" do
      other = create(:journey, :launched, customer: customer, name: "Enrol from student", definition: record_definition)
      expect(errors).to eq([message(:record_start_taken, name: other.name)])

      other.update!(definition: record_definition.sub("student_add_course", "enrolment_new"))
      expect(errors).to eq([])
    end

    it "does not clash with a journey that creates on the same page" do
      create(:journey, :launched, customer: customer, definition: { "steps" => [
        { "key" => "start", "kind" => "create", "action_key" => "student_add_course" },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
      ] }.to_json)

      expect(errors).to eq([])
    end
  end

  context "with a step that edits a record an earlier page created" do
    let(:journey) do
      create(:journey, customer: customer, definition: { "steps" => [
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "review", "kind" => "update", "action_key" => "student_new", "record" => "start" },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
      ] }.to_json)
    end

    before { student_journey_page }

    it "passes, the first page still having to create" do
      expect(errors).to eq([])

      journey_page(student_entity, action_key: "student_edit", fields: [journey_text_field("full_name")],
                                   form_settings: { modes: ["update"] })
      journey.update!(definition: journey.definition.sub(%("action_key":"student_new"), %("action_key":"student_edit")))
      expect(described_class.new(journey).errors)
        .to eq([message(:start_not_create, step: "start", audience: I18n.t("journeys.audiences.admin"))])
    end

    it "is never for public visitors" do
      journey.update!(visible_audiences: %w[admin public])

      expect(errors).to include(message(:update_not_public))
    end
  end

  context "when the journey opens by creating a user account" do
    let(:user_definition) do
      { "steps" => [
        { "key" => "user", "kind" => "user" },
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" } },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
      ] }.to_json
    end
    let(:journey) { create(:journey, customer: customer, name: "Register student", definition: user_definition) }
    let(:student_modes) { %w[create update] }

    before do
      student_entity.update_columns(extended_model: EntityDefinitions::Capabilities::PERSON_MODEL)
      journey_page(student_entity, action_key: "student_new", fields: [journey_text_field("full_name")],
                                   form_settings: { modes: student_modes })
      course_journey_page
    end

    it "passes when the page after the user step saves a person record" do
      expect(errors).to eq([])
    end

    it "is for admins only" do
      journey.update!(visible_audiences: %w[admin public])

      expect(errors).to include(message(:user_start_admin_only))
    end

    it "needs the page after the user step to be on a person entity" do
      student_entity.update_columns(extended_model: nil)

      expect(errors).to eq([message(:user_page_not_person, step: "start")])
    end

    context "when the page after the user step only edits records" do
      let(:student_modes) { %w[update] }

      it "names it a start that can't create" do
        expect(errors).to eq([message(:start_not_create, step: "start", audience: I18n.t("journeys.audiences.admin"))])
      end
    end

    it "refuses a second live journey opening with a user step before the same page, but not a plain create journey" do
      create(:journey, :launched, customer: customer)
      expect(errors).to eq([])

      other = create(:journey, :launched, customer: customer, name: "Enrol", definition: user_definition)
      expect(errors).to eq([message(:user_start_taken, name: other.name)])
    end
  end

  it "reports definition errors before looking up pages" do
    journey.update!(definition: { "steps" => [] }.to_json)

    expect(errors).to eq(journey.steps_definition.errors)
  end
end
