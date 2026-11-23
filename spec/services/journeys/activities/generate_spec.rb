# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::Activities::Generate do
  include JourneyPageHelpers

  let(:customer) { create(:customer) }
  include_context "student course association"

  let(:domain) { create(:entity_domain, customer: customer, name: "School") }

  before do
    [student_entity, course_entity].each { |entity| EntityDomains::Memberships.place!(entity, domain) }
  end

  def make_person!(entity)
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    entity.update_columns(extended_model: person_model)
  end

  def page_fields(page) = page.configuration_json["pages"].flat_map { |step| Array(step["fields"]) }
  def field(page, slug) = page_fields(page).find { |item| item["property_slug"] == slug }

  def generate(candidate = "create-#{student_entity.id}", domain_id: domain.id)
    described_class.call(customer: customer, domain_id: domain_id, candidate_key: candidate)
  end
  def page(action_key) = Page.find_by(customer_id: customer.id, action_key: action_key)
  def counts = [Page.unscoped.count, PageVersion.count, Journey.count]

  describe "a first generation" do
    subject(:result) { generate }

    it "creates a launched admin Student page that only adds records" do
      expect(result.ok).to be(true)
      start = page("student_new")
      expect([start.launched?, start.visible_audiences, start.entity_id.to_s]).to eq([true, %w[admin], student_entity.id.to_s])
      expect(start.submission_modes).to eq(%w[create])
    end

    it "creates a launched admin bridge page with the student locked in" do
      result
      bridge = page("student_add_course")
      expect([bridge.launched?, bridge.visible_audiences, bridge.entity_id.to_s]).to eq([true, %w[admin], bridge_entity.id.to_s])
      expect(bridge.name).to eq(I18n.t("journeys.generate.relate_page_name", target: "Course", parent: "Student"))
      expect(bridge.page_inputs).to eq([{ "field" => "student", "entity_id" => student_entity.id.to_s }])
      expect(bridge.serves?(:create)).to be(true)
    end

    it "records the page set-up as a version of each page" do
      result
      bridge = page("student_add_course")
      expect(bridge.current_version.description).to eq(I18n.t("journeys.generate.version_description"))
      expect(bridge.resolved_current_version.content.payload).to include('"inputs"')
    end

    it "saves a draft admin journey: start, a repeating relate step that can be skipped, then the student's record" do
      journey = result.journey
      expect([journey.draft?, journey.visible_audiences, journey.entity_domain, journey.key])
        .to eq([true, %w[admin], domain, "student_journey"])
      expect(journey.name).to eq(I18n.t("journeys.generate.journey_name", start: "Student"))
      expect(journey.steps_definition.to_h["steps"]).to eq([
        { "key" => "start", "kind" => "create", "action_key" => "student_new", "inputs" => {}, "repeat" => false,
          "optional" => false },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course",
          "inputs" => { "student" => "start" }, "repeat" => true, "optional" => true },
        { "key" => "finish", "kind" => "finish", "inputs" => {}, "repeat" => false, "optional" => false,
          "target" => { "kind" => "record", "step" => "start" } }
      ])
    end

    it "passes the journey launch checks and starts on its first page once launched" do
      journey = result.journey
      expect(Journeys::LaunchChecks.new(journey).errors).to eq([])

      journey.update!(status: :launched)
      expect(Journeys::Starter.for_page(page: page("student_new"), audience: "admin", customer_id: customer.id)).to eq(journey)
    end

    it "binds its pages to the customer's own Save page record once the shared one is deleted" do
      Flowcharts::DefaultPageFlowchart.fetch.update_columns(status: Flowchart.statuses[:deleted])

      journey = result.journey
      copy = Flowcharts::DefaultPageFlowchart.for_customer(customer)

      expect(copy.customer_id).to eq(customer.id)
      expect([page("student_new").flowchart, page("student_add_course").flowchart]).to eq([copy, copy])
      expect(Journeys::LaunchChecks.new(journey).errors).to eq([])
    end
  end

  it "launches the admin bridge page when the start entity is a person, so the link rows are member-owned" do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    student_entity.update_columns(extended_model: person_model)
    expect(People::Ownership.kind(Entity.find(bridge_entity.id))).to eq(:owned)

    expect(generate.ok).to be(true)
    expect(page("student_add_course")).to have_attributes(launched: true, visible_audiences: %w[admin])
  end

  it "reuses both pages on a second run and suffixes the journey key" do
    first = generate.journey

    expect { @second = generate }.not_to(change { [Page.unscoped.count, PageVersion.count] })
    expect(@second.ok).to be(true)
    expect(@second.journey.key).to eq("student_journey_2")
    expect(@second.journey.steps_definition.action_keys).to eq(first.steps_definition.action_keys)
  end

  it "reuses the assistant's admin form for the start page instead of composing a second one" do
    form = Current.with_customer(customer) { AiAssistant::Assistant::GeneratePage.call(entity: student_entity, customer: customer) }.page

    expect(generate.ok).to be(true)
    expect(page("student_new")).to eq(form)
    expect(Page.where(customer_id: customer.id).for_entity(student_entity.id).count).to eq(1)
  end

  it "reuses the form built from the entity's current version once the entity has changed" do
    Current.with_customer(customer) { AiAssistant::Assistant::GeneratePage.call(entity: student_entity, customer: customer) }
    student_entity.property_schema = [{ "name" => "Full Name", "name_slug" => "full_name", "html_type" => "text" },
                                      { "name" => "Email", "name_slug" => "email", "html_type" => "email" }].to_json
    student_entity.save!
    current = Current.with_customer(customer) { AiAssistant::Assistant::GeneratePage.call(entity: student_entity.reload, customer: customer) }.page

    expect(current.action_key).to eq("student_new_2")
    expect(generate.journey.steps_definition.page_steps.first.action_key).to eq("student_new_2")
  end

  it "keeps an entity's version page for its admin form when a step locks in a record" do
    generate

    expect(page("student_new").entity_version_id).to eq(student_entity.reload.current_version_id)
    expect(page("student_add_course").entity_version_id).to be_nil
  end

  it "returns ok: false and writes nothing for an unknown candidate" do
    expect { @result = generate("create-0") }.not_to(change { counts })
    expect([@result.ok, @result.journey, @result.errors]).to eq([false, nil, [I18n.t("journeys.admin.generation.no_candidates")]])
  end

  it "refuses a candidate of a record type outside the domain and writes nothing" do
    outsider = create(:entity, customer: customer, name: "Club", display_label: "Club")

    expect { @result = generate("create-#{outsider.id}") }.not_to(change { counts })
    expect([@result.ok, @result.journey]).to eq([false, nil])
  end

  it "generates the course's create journey, adding students from the course end" do
    journey = generate("create-#{course_entity.id}").journey

    expect(journey.key).to eq("course_journey")
    expect(journey.steps_definition.steps.map { |step| [step.kind, step.action_key, step.inputs, step.optional] })
      .to eq([["create", "course_new", {}, false], ["relate", "course_add_student", { "course" => "start" }, true], ["finish", nil, {}, false]])
    expect(page("course_new")).to have_attributes(launched: true, visible_audiences: %w[admin])
    expect(Journeys::LaunchChecks.new(journey).errors).to eq([])
  end

  describe "a journey started from an existing record" do
    subject(:journey) { generate("record-#{student_entity.id}-#{bridge_entity.id}-student").journey }

    it "opens with the student, then the course page with the student locked in, finishing on the student" do
      expect([journey.draft?, journey.visible_audiences, journey.key]).to eq([true, %w[admin], "student_add_course_journey"])
      expect(journey.name).to eq(I18n.t("journeys.generate.relate_page_name", target: "Course", parent: "Student"))
      expect(journey.steps_definition.to_h["steps"]).to eq([
        { "key" => "record", "kind" => "record", "entity_id" => student_entity.id.to_s, "inputs" => {}, "repeat" => false,
          "optional" => false },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course",
          "inputs" => { "student" => "record" }, "repeat" => true, "optional" => false },
        { "key" => "finish", "kind" => "finish", "inputs" => {}, "repeat" => false, "optional" => false,
          "target" => { "kind" => "record", "step" => "record" } }
      ])
      expect(page("student_new")).to be_nil
    end

    it "passes the launch checks and shares the course page with the create journey" do
      expect(Journeys::LaunchChecks.new(journey).errors).to eq([])
      expect { generate }.to change(Page, :count).by(1)
      expect(Journey.find_by(key: "student_journey").steps_definition.action_keys.last).to eq("student_add_course")
    end
  end

  it "adds students from a course with a labelled student picker in place of the bare id" do
    journey = generate("record-#{course_entity.id}-#{bridge_entity.id}-course").journey
    bridge = page("course_add_student")

    expect(bridge.page_inputs).to eq([{ "field" => "course", "entity_id" => course_entity.id.to_s }])
    expect(field(bridge, "student")).to include("field_type" => "select", "html_type" => "select",
                                                "dynamic_options" => include("options_source" => "entity_entries",
                                                                             "entity_id" => student_entity.id.to_s))
    expect(field(bridge, "course")["dynamic_options"]).to include("entity_id" => course_entity.id.to_s)
    expect(Journeys::LaunchChecks.new(journey).errors).to eq([])
  end

  context "when the link rows are owned by the member that is the student" do
    before { make_person!(student_entity) }

    it "builds a member page to choose a course, without the student or what admins set" do
      result = generate("member-#{bridge_entity.id}")
      choose = page("member_choose_course")

      expect(result.ok).to be(true)
      expect([choose.launched?, choose.visible_audiences, choose.entity_id]).to eq([true, %w[member], bridge_entity.id])
      expect(choose.name).to eq(I18n.t("journeys.generate.member_choose_name", target: "Course"))
      expect(page_fields(choose).map { |item| item["property_slug"] }).to include("course", "status")
      expect(page_fields(choose).map { |item| item["property_slug"] }).not_to include("student", "grade")
      journey = result.journey
      expect([journey.visible_audiences, journey.key]).to eq([%w[member], "member_choose_course_journey"])
      expect(journey.steps_definition.steps.map { |step| [step.kind, step.action_key] }).to eq([["create", "member_choose_course"], ["finish", nil]])
      expect(Journeys::LaunchChecks.new(journey).errors).to eq([])
    end

    context "with a record the member owns that has rows hanging off it" do
      let(:order_entity) do
        create(:entity, customer: customer, name: "Order", display_label: "Order", property_schema: [
          { "name" => "Student", "name_slug" => "student", "html_type" => "select", "type" => "EntityReference",
            "entity_id" => student_entity.id.to_s, "validators" => [{ "type" => "presence" }] },
          { "name" => "Number", "name_slug" => "number", "html_type" => "text" }
        ].to_json)
      end
      let(:line_bridge) do
        order_entity.associations_json = [{ "target_entity_id" => course_entity.id, "target_entity_name" => course_entity.name,
                                            "display_field" => "code", "display_field_label" => "Code",
                                            "additional_attributes" => [{ "name" => "Quantity", "name_slug" => "quantity",
                                                                          "html_type" => "number" }] }]
        order_entity.save!
        order_entity.sync_bridge_entities!
        Entity.find_by!(name: "assoc_order_course", customer_id: customer.id)
      end

      before do
        line_bridge
        EntityDomains::Memberships.place!(order_entity.reload, domain)
      end

      it "builds the member's order page, then a repeatable, skippable member page adding its lines with the order locked in" do
        result = generate("member-#{order_entity.id}")
        lines = page("member_order_add_course")

        expect(result.ok).to be(true)
        expect(result.journey.steps_definition.steps.map { |step| [step.kind, step.action_key, step.inputs, step.repeat, step.optional] })
          .to eq([["create", "member_new_order", {}, false, false], ["relate", "member_order_add_course", { "order" => "start" }, true, true],
                  ["finish", nil, {}, false, false]])
        expect([lines.launched?, lines.visible_audiences, lines.entity_id]).to eq([true, %w[member], line_bridge.id])
        expect(lines.page_inputs).to eq([{ "field" => "order", "entity_id" => order_entity.id.to_s }])
        expect(field(lines, "course")).to include("field_type" => "select",
                                                  "dynamic_options" => include("entity_id" => course_entity.id.to_s))
        expect(page_fields(page("member_new_order")).map { |item| item["property_slug"] }).not_to include("student")
        expect(Journeys::LaunchChecks.new(result.journey).errors).to eq([])
      end

      it "leaves the admin page adding the same rows alone" do
        generate("create-#{order_entity.id}")

        expect { generate("member-#{order_entity.id}") }.to change(Page, :count).by(2)
        expect(page("order_add_course").visible_audiences).to eq(%w[admin])
      end

      it "reuses the member pages on a second run" do
        generate("member-#{order_entity.id}")

        expect { @second = generate("member-#{order_entity.id}") }.not_to(change { [Page.unscoped.count, PageVersion.count] })
        expect(@second.journey.steps_definition.action_keys).to eq(%w[member_new_order member_order_add_course])
      end
    end

    it "opens the student's create journey by creating the user account its record is linked to" do
      journey = generate.journey

      expect(journey.steps_definition.steps.map { |step| [step.key, step.kind, step.action_key] })
        .to eq([%w[user user] + [nil], %w[start create student_new], %w[relate_1 relate student_add_course], ["finish", "finish", nil]])
      expect(journey.steps_definition.account_step.key).to eq("start")
      expect(Journeys::LaunchChecks.new(journey).errors).to eq([])
    end

    describe "a public sign-up that continues on the member page" do
      subject(:result) { generate("public-#{bridge_entity.id}") }

      it "builds a public Student page with the account fields first, bound to the sign-up flowchart" do
        expect(result.ok).to be(true)
        signup = page("signup_choose_course")

        expect([signup.launched?, signup.visible_audiences, signup.entity_id]).to eq([true, %w[public], student_entity.id])
        expect(signup.serves?(:create)).to be(true)
        expect(signup.flowchart).to eq(Flowcharts::SignUpPageFlowchart.fetch)
        fields = page_fields(signup)
        expect(fields.first(3).map { |item| item.values_at("property_slug", "source", "html_type", "required") })
          .to eq([["first_name", "identity", "text", true], ["last_name", "identity", "text", true], ["email", "identity", "email", true]])
        expect(fields.first["label"]).to eq(I18n.t("member.profiles.show.fields.first_name"))
        expect(fields.map { |item| item["property_slug"] }).to include("full_name")
        expect(fields.map { |item| item["order"] }).to eq((0...fields.size).to_a)
      end

      it "saves a draft public journey finishing on the member page, which it also builds" do
        journey = result.journey

        expect([journey.draft?, journey.visible_audiences, journey.key]).to eq([true, %w[public], "signup_choose_course_journey"])
        expect(journey.name).to eq(I18n.t("journeys.generate.signup_then_name", next: I18n.t("journeys.generate.member_choose_name", target: "Course")))
        expect(journey.steps_definition.to_h["steps"]).to eq([
          { "key" => "start", "kind" => "create", "action_key" => "signup_choose_course", "inputs" => {}, "repeat" => false,
            "optional" => false },
          { "key" => "finish", "kind" => "finish", "inputs" => {}, "repeat" => false, "optional" => false,
            "target" => { "kind" => "page", "action_key" => "member_choose_course" } }
        ])
        expect(page("member_choose_course")).to have_attributes(launched: true, visible_audiences: %w[member])
        expect(Journeys::LaunchChecks.new(journey).errors).to eq([])
      end

      it "reuses the sign-up and member pages on a second run" do
        result

        expect { @second = generate("public-#{bridge_entity.id}") }.not_to(change { Page.unscoped.count })
        expect(@second.journey.key).to eq("signup_choose_course_journey_2")
      end

      it "does not reuse a public page under the key that isn't a sign-up page" do
        journey_page(student_entity, action_key: "signup_choose_course", fields: [journey_text_field("full_name")],
                                     form_settings: { modes: ["create"] }, visible_audiences: %w[public])

        expect(result.journey.steps_definition.first_step.action_key).to eq("signup_choose_course_2")
      end

      it "binds the sign-up page to the customer's own sign-up flowchart once the shared one is deleted" do
        Flowcharts::SignUpPageFlowchart.fetch.update_columns(status: Flowchart.statuses[:deleted])

        expect(result.ok).to be(true)
        expect(page("signup_choose_course").flowchart).to have_attributes(customer_id: customer.id, launched?: true)
        expect(page("signup_choose_course").flowchart).to eq(Flowcharts::SignUpPageFlowchart.for_customer(customer))
        expect(Journeys::LaunchChecks.new(result.journey).errors).to eq([])
      end

      it "writes nothing when no sign-up flowchart can be had" do
        allow(Flowcharts::SignUpPageFlowchart).to receive(:for_customer).and_return(nil)

        expect { @result = generate("public-#{bridge_entity.id}") }.not_to(change { counts })
        expect([@result.ok, @result.errors]).to eq([false, [I18n.t("journeys.generate.signup_unavailable")]])
      end
    end
  end

  it "refuses another customer's domain" do
    expect(generate(domain_id: create(:entity_domain).id).ok).to be(false)
  end

  it "rolls back pages already created when a later page fails" do
    allowed = Billing::Quota::Guard.check(customer: customer, item_key: "page")
    denied = allowed.class.new(**allowed.to_h, allowed: false)
    allow(Billing::Quota::Guard).to receive(:check).and_return(allowed, denied)

    expect { @result = generate }.not_to(change { counts })
    expect([@result.ok, @result.errors]).to eq([false, [denied.message]])
  end

  context "when the customer already has pages" do
    it "does not reuse or edit a launched page under the key that does not add records" do
      existing = journey_page(student_entity, action_key: "student_new", fields: [journey_text_field("full_name")],
                                              form_settings: { modes: ["update"] })

      expect { @result = generate }.not_to(change { existing.reload.current_version_id })
      expect(@result.journey.steps_definition.first_step.action_key).to eq("student_new_2")
      expect(page("student_new_2").serves?(:create)).to be(true)
    end

    it "reuses a fitting page from the suffixed key family on the next run" do
      journey_page(student_entity, action_key: "student_new", fields: [journey_text_field("full_name")],
                                   form_settings: { modes: ["update"] })
      generate

      expect { @result = generate }.not_to(change { Page.unscoped.count })
      expect(@result.journey.steps_definition.first_step.action_key).to eq("student_new_2")
    end

    it "does not reuse a bridge page that lacks the locked input" do
      journey_page(bridge_entity, action_key: "student_add_course",
                                  fields: [journey_reference_field("student", student_entity, "full_name"),
                                           journey_reference_field("course", course_entity, "code"), journey_text_field("status")],
                                  form_settings: { modes: ["create"] })

      expect(generate.journey.steps_definition.action_keys.last).to eq("student_add_course_2")
    end

    it "does not reuse a bridge page that locks more than the student" do
      journey_page(bridge_entity, action_key: "student_add_course",
                                  fields: [journey_reference_field("student", student_entity, "full_name"),
                                           journey_reference_field("course", course_entity, "code"), journey_text_field("status")],
                                  form_settings: { modes: ["create"], inputs: [{ field: "student", entity_id: student_entity.id.to_s },
                                                                               { field: "course", entity_id: course_entity.id.to_s }] })

      expect(generate.journey.steps_definition.action_keys.last).to eq("student_add_course_2")
    end

    it "builds a second page when the entity's current version already has a generated page" do
      version = student_entity.resolved_current_version(customer.id)
      Pages::Activities::CreateFromEntityVersion.call(entity: student_entity, version: version, customer: customer)

      expect(generate.ok).to be(true)
      expect(page("student_new")).to have_attributes(launched: true, entity_version_id: nil)
    end

    it "builds a fresh page instead of restoring a trashed one generated from the same version" do
      version = student_entity.resolved_current_version(customer.id)
      trashed = Pages::Activities::CreateFromEntityVersion.call(entity: student_entity, version: version, customer: customer).page
      trashed.update!(action_key: "old_student_form")
      trashed.soft_delete

      expect { @result = generate }.to change { Page.with_deleted.where(customer_id: customer.id).for_entity(student_entity.id).count }.by(1)
      expect(page("student_new").id).not_to eq(trashed.id)
      expect(Page.unscoped.find(trashed.id)).to have_attributes(status: "inactive", action_key: "old_student_form")
    end

    it "keeps clear of keys held by trashed pages" do
      journey_page(student_entity, action_key: "student_new", fields: [journey_text_field("full_name")]).soft_delete

      expect(generate.journey.steps_definition.first_step.action_key).to eq("student_new_2")
    end

    it "ignores other customers' pages" do
      other = create(:customer)
      Current.set(customer: other) do
        other_entity = create(:entity, customer: other)
        create(:page, customer: other, entity: other_entity, launched: true, action_key: "student_new")
      end

      expect(generate.journey.steps_definition.first_step.action_key).to eq("student_new")
      expect(page("student_new").customer_id).to eq(customer.id)
    end
  end

  it "builds valid keys for entities whose names have no ASCII letters" do
    parent = create(:entity, customer: customer, name: "学生", display_label: "学生",
                             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    note = create(:entity, customer: customer, name: "笔记", display_label: "笔记", property_schema: [
      { "name" => "Student", "name_slug" => "student", "html_type" => "select",
        "config" => { "options_source" => "entity_entries", "entity_id" => parent.id.to_s, "label_field" => "name" } },
      { "name" => "Body", "name_slug" => "body", "html_type" => "text" }
    ].to_json)
    other_domain = create(:entity_domain, customer: customer)
    [parent, note].each { |entity| EntityDomainMembership.create!(customer: customer, entity_domain: other_domain, entity: entity) }

    journey = generate("create-#{parent.id}", domain_id: other_domain.id).journey
    keys = [journey.key, *journey.steps_definition.action_keys]
    expect(keys).to eq(["entity_#{parent.id}_journey", "entity_#{parent.id}_new", "entity_#{parent.id}_add_entity_#{note.id}"])
    expect(Journeys::LaunchChecks.new(journey).errors).to eq([])
  end
end
