# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::LaunchChecks do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:required) { [{ "type" => "presence" }] }
  let(:hidden_from_members) { { "admin" => true, "member" => false, "public" => false } }

  around { |example| Current.set(customer: customer) { example.run } }

  # Definitions are written without validation so fixtures can hold derived
  # fields and associations without satisfying the editor's rules.
  def define(name, schema, associations: [], **attributes)
    entity = create(:entity, customer: customer, name: name, **attributes)
    entity.property_schema_json = schema
    entity.associations_json = associations
    entity.save!(validate: false)
    Entity.find(entity.id)
  end

  def attribute(slug, name, **extra)
    { "name" => name, "name_slug" => slug, "type" => "String", "html_type" => "text" }.merge(extra.transform_keys(&:to_s))
  end

  def input(slug, **extra)
    { "id" => "f_#{slug}", "field_type" => "text", "html_type" => "text", "property_slug" => slug,
      "property_type" => "string", "label" => slug.humanize, "source" => "entity" }.merge(extra.transform_keys(&:to_s))
  end

  def identity_input(key, **extra)
    html = key == "email" ? "email" : "text"
    { "id" => "id_#{key}", "field_type" => html, "html_type" => html, "property_slug" => key,
      "property_type" => "string", "label" => key.humanize, "source" => "identity" }.merge(extra.transform_keys(&:to_s))
  end

  def columns(*fields)
    { "id" => "cols_#{fields.size}", "field_type" => "columns", "property_type" => "layout",
      "columns" => [{ "fields" => fields }] }
  end

  def form(entity, fields, audiences: %w[admin], form_settings: nil, **attrs)
    config = { "pages" => [{ "id" => "p1", "name" => "Step 1", "order" => 1, "fields" => fields }] }
    config["form_settings"] = form_settings if form_settings
    page = build(:page, customer: customer, entity: entity, configuration: config.to_json, **attrs)
    page.visible_audiences = audiences
    page.save!(validate: false)
    page.update_column(:flowchart_id, Flowcharts::DefaultPageFlowchart.fetch.id) if page.flowchart_id.blank?
    Page.find(page.id)
  end

  def checks(page) = described_class.new(page)
  def audience(key) = I18n.t("common.visibility.#{key}")
  def message(key, **vars) = I18n.t("maint_core.errors.page_launch.#{key}", **vars)

  def person_ref(slug, name, target, owner: false, **extra)
    attribute(slug, name, html_type: "select", owner: owner, config: {
      "options_source" => "entity_entries", "entity_id" => target.id.to_s, "label_field" => "name"
    }, **extra)
  end

  describe "#reference_errors" do
    let(:instructor) { define("Instructor", [attribute("full_name", "姓名", visibility: hidden_from_members)]) }
    let(:dropdown) { { "options_source" => "entity_entries", "entity_id" => instructor.id, "label_field" => "full_name" } }
    let(:course) { define("Course", [attribute("instructor", "授课教师", html_type: "select", config: dropdown)]) }

    def instructor_field(**extra)
      input("instructor", label: "授课教师", html_type: "select", dynamic_options: dropdown, **extra)
    end

    it "blocks a dropdown whose display field an audience of the form can't see" do
      page = form(course, [instructor_field], audiences: %w[admin member])

      expect(checks(page).reference_errors).to eq([
        message(:reference_label_hidden, field: "授课教师", label: "姓名", audience: audience("member"))
      ])
    end

    it "passes when every audience of the form can see the display field" do
      expect(checks(form(course, [instructor_field])).reference_errors).to eq([])
    end

    it "blocks a dropdown whose target is trashed or missing, once per field" do
      ghost = input("ghost", label: "Ghost", html_type: "select", dynamic_options: dropdown.merge("entity_id" => 0))
      page = form(course, [instructor_field, ghost], audiences: %w[admin member public])
      # Course still references Instructor, so the trash guard would refuse soft_delete.
      instructor.update_column(:status, Entity.statuses[:inactive])

      expect(checks(page).reference_errors).to eq([
        message(:reference_target_inactive, field: "授课教师"),
        message(:reference_target_inactive, field: "Ghost")
      ])
    end

    it "finds dropdowns inside columns containers" do
      page = form(course, [columns(instructor_field)], audiences: %w[admin member])

      expect(checks(page).reference_errors.size).to eq(1)
    end
  end

  describe "#required_field_errors" do
    let(:student) do
      define("Student", [
        attribute("full_name", "姓名", validators: required),
        attribute("email", "Email", validators: required, visibility: hidden_from_members),
        attribute("nickname", "Nickname", validators: required, default_value: "Pal"),
        attribute("motto", "Motto", validators: [{ "type" => "numericality" }]),
        attribute("double_score", "Double score", type: "Calculated", html_type: "number", formula: "1 + 1", validators: required)
      ])
    end

    it "lists each required attribute missing from the form, for every audience of the form" do
      page = form(student, [input("motto")], audiences: %w[admin member])

      expect(checks(page).required_field_errors).to eq([
        message(:required_field_missing, field: "姓名", audience: audience("admin")),
        message(:required_field_missing, field: "Email", audience: audience("admin")),
        message(:required_field_missing, field: "Nickname", audience: audience("admin")),
        message(:required_field_missing, field: "姓名", audience: audience("member")),
        message(:required_field_missing, field: "Nickname", audience: audience("member"))
      ])
    end

    it "asks nothing of a page that only edits records, which keep what the form doesn't post" do
      page = form(student, [input("motto")], audiences: %w[admin member], form_settings: { "modes" => %w[update] })

      expect(checks(page).required_field_errors).to eq([])
    end

    it "is satisfied by fields without a source and by fields inside columns" do
      page = form(student, [input("full_name", source: nil), columns(input("email"), input("nickname"))])

      expect(checks(page).required_field_errors).to eq([])
    end

    it "does not count a base-model field with the same slug" do
      page = form(student, [input("full_name", source: "base_model"), input("email"), input("nickname")])

      expect(checks(page).required_field_errors).to eq([
        message(:required_field_missing, field: "姓名", audience: audience("admin"))
      ])
    end

    context "with a link entity" do
      let(:student) { define("Student", [attribute("full_name", "姓名")], display_label: "学生") }
      let(:course) { define("Course", [attribute("title", "Title")]) }
      let(:bridge) do
        define("assoc_course_student", [
          attribute("course", "Course", type: "EntityReference", entity_id: course.id, validators: required),
          attribute("student", "Student", type: "EntityReference", entity_id: student.id, validators: required),
          attribute("status", "Status", html_type: "select", validators: required),
          attribute("grade", "Grade", validators: required, visibility: hidden_from_members)
        ], category: :bridge)
      end
      let(:linked_course) do
        course.associations_json = [{ "target_entity_id" => student.id, "target_entity_name" => "Student",
                                      "bridge_entity_id" => bridge.id, "bridge_entity_name" => bridge.name }]
        course.save!(validate: false)
        Entity.find(course.id)
      end

      def link(slug, section: bridge.name, **extra)
        input(slug, source: "bridge", source_section: section, **extra)
      end

      it "requires the link's required fields once the link is on the form, except the reference back" do
        page = form(linked_course, [input("title"), link("student")], audiences: %w[admin member])

        expect(checks(page).required_field_errors).to eq([
          message(:required_link_field_missing, field: "Status", target: "学生", audience: audience("admin")),
          message(:required_link_field_missing, field: "Grade", target: "学生", audience: audience("admin")),
          message(:required_link_field_missing, field: "Status", target: "学生", audience: audience("member"))
        ])
      end

      it "matches a link section by the link entity's id" do
        section = bridge.id.to_s
        page = form(linked_course, [link("student", section: section), link("status", section: section), link("grade", section: section)])

        expect(checks(page).required_field_errors).to eq([])
      end

      it "skips a link with no field on the form" do
        expect(checks(form(linked_course, [input("title")])).required_field_errors).to eq([])
      end
    end

    it "skips the owner reference for members because the server fills it" do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      student = define("Student", [attribute("name", "Name")], extended_model: person_model)
      assignment = define("Assignment", [
        attribute("title", "Title", validators: required),
        person_ref("student", "Student", student, owner: true, validators: required)
      ])
      page = form(assignment, [], audiences: %w[admin member])

      expect(checks(page).required_field_errors).to eq([
        message(:required_field_missing, field: "Title", audience: audience("admin")),
        message(:required_field_missing, field: "Student", audience: audience("admin")),
        message(:required_field_missing, field: "Title", audience: audience("member"))
      ])
      expect(checks(page).required_field_errors(%w[member])).to eq([
        message(:required_field_missing, field: "Title", audience: audience("member"))
      ])
    end
  end

  describe "#audience_errors" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:student) do
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      define("Student", [attribute("name", "Name")], extended_model: person_model, display_label: "Student")
    end
    let(:teacher) do
      define("Teacher", [attribute("name", "Name")], extended_model: person_model, display_label: "Teacher")
    end
    let(:course) { define("Course", [attribute("title", "Title")], display_label: "Course") }
    let(:assignment) do
      define("Assignment", [
        attribute("title", "Title"),
        person_ref("student", "Student", student, owner: true)
      ], display_label: "Assignment")
    end
    let(:review) do
      define("Review", [
        person_ref("student", "Student", student),
        person_ref("teacher", "Teacher", teacher)
      ], display_label: "Review")
    end
    let(:enrollment) do
      define("Enrollment", [
        attribute("student", "Student", type: "EntityReference", entity_id: student.id, html_type: "select"),
        attribute("course", "Course", type: "EntityReference", entity_id: course.id, html_type: "select")
      ], category: :bridge, display_label: "Enrollment")
    end

    def person_dropdown(slug, target, label: slug.humanize)
      input(slug, label: label, html_type: "select", dynamic_options: {
        "options_source" => "entity_entries", "entity_id" => target.id, "label_field" => "name"
      })
    end

    it "blocks the public audience on a page bound to an owned or private entity" do
      owned_page = form(assignment, [input("title")], audiences: %w[admin member public])
      private_page = form(review, [person_dropdown("student", student, label: "Student")], audiences: %w[admin member public])

      expect(checks(owned_page).audience_errors).to include(
        message(:owned_entity_public_audience, entity: "Assignment")
      )
      expect(checks(private_page).audience_errors).to include(
        message(:owned_entity_public_audience, entity: "Review")
      )
    end

    it "allows a member page on an owned entity and a public page on an open entity" do
      expect(checks(form(assignment, [input("title")], audiences: %w[admin member])).audience_errors).to eq([])
      expect(checks(form(course, [input("title")], audiences: %w[admin member public])).audience_errors).to eq([])
    end

    it "blocks the public audience when the form carries an owned or private bridge section" do
      course.associations_json = [{
        "target_entity_id" => student.id, "target_entity_name" => student.name,
        "bridge_entity_id" => enrollment.id, "bridge_entity_name" => enrollment.name
      }]
      course.save!(validate: false)
      linked = Entity.find(course.id)
      page = form(linked, [
        input("title"),
        input("student", source: "bridge", source_section: enrollment.name, label: "Student")
      ], audiences: %w[admin member public])

      expect(checks(page).audience_errors).to include(
        message(:owned_entity_public_audience, entity: "Enrollment")
      )
    end

    it "blocks a reference whose target isn't visible to an audience of the form" do
      public_person = form(course, [person_dropdown("instructor", student, label: "Instructor")], audiences: %w[admin member public])
      member_private = form(course, [person_dropdown("review", review, label: "Review")], audiences: %w[admin member])
      public_open = form(student, [person_dropdown("course", course, label: "Course")], audiences: %w[admin member public])

      expect(checks(public_person).audience_errors).to include(
        message(:reference_private_for_audience, field: "Instructor", target: "Student", audience: audience("public"))
      )
      expect(checks(member_private).audience_errors).to include(
        message(:reference_private_for_audience, field: "Review", target: "Review", audience: audience("member"))
      )
      expect(checks(public_open).audience_errors).to eq([])
    end

    it "takes an explicit audiences list so a live page can re-check only what it gained" do
      page = form(assignment, [input("title")])

      expect(checks(page).audience_errors(%w[member])).to eq([])
      expect(checks(page).audience_errors(%w[public])).to eq([
        message(:owned_entity_public_audience, entity: "Assignment")
      ])
    end

    it "blocks a bridge-bound page unless its audiences are exactly member" do
      page = form(enrollment, [input("course")], audiences: %w[member])
      expect(checks(page).audience_errors).to eq([])

      with_admin = form(enrollment, [input("course")], audiences: %w[admin member])
      expect(checks(with_admin).audience_errors).to eq([message(:bridge_page_member_only)])

      public_only = form(enrollment, [input("course")], audiences: %w[public])
      expect(checks(public_only).audience_errors).to include(message(:bridge_page_member_only))
    end

    it "admits admins to a bridge-bound page whose owner reference is a locked input" do
      locked = ->(field) { { "inputs" => [{ "field" => field, "entity_id" => student.id.to_s }] } }

      admin = form(enrollment, [input("course")], audiences: %w[admin], form_settings: locked.call("student"))
      expect(checks(admin).audience_errors).to eq([])

      admin_member = form(enrollment, [input("course")], audiences: %w[admin member], form_settings: locked.call("student"))
      expect(checks(admin_member).audience_errors).to eq([])

      other_field = form(enrollment, [input("student")], audiences: %w[admin], form_settings: locked.call("course"))
      expect(checks(other_field).audience_errors).to eq([message(:bridge_page_member_only)])

      with_public = form(enrollment, [input("course")], audiences: %w[admin public], form_settings: locked.call("student"))
      expect(checks(with_public).audience_errors).to include(message(:bridge_page_member_only))
    end

    it "refuses to save a live admin bridge page that drops its locked owner input" do
      live = form(enrollment, [input("course")], audiences: %w[admin],
                                                 form_settings: { "inputs" => [{ "field" => "student", "entity_id" => student.id.to_s }] })
      live.update_column(:launched, true)
      expect(live.reload).to be_valid

      live.configuration = live.configuration_json.merge("form_settings" => {}).to_json
      expect(live).not_to be_valid
      expect(live.errors[:base]).to include(message(:bridge_page_member_only))

      live.launched = false
      expect(live).to be_valid
    end
  end

  describe "#identity_errors" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:student) do
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      define("Student", [attribute("name", "Name")], extended_model: person_model)
    end
    let(:course) do
      define("Course", [
        attribute("title", "Title"),
        attribute("email", "Email", validators: required)
      ], display_label: "Course")
    end

    it "blocks a non-person page that carries an identity field" do
      page = form(course, [input("title"), identity_input("email")], audiences: %w[admin public])

      expect(checks(page).identity_errors).to eq([message(:identity_field_not_person)])
      expect(page.launch_errors).to include(message(:identity_field_not_person))
    end

    it "allows identity fields on a person-entity page" do
      page = form(student, [input("name"), identity_input("email"), identity_input("first_name")], audiences: %w[admin public])

      expect(checks(page).identity_errors).to eq([])
    end

    it "does not treat an identity field as a present entity attribute" do
      page = form(course, [identity_input("email")], audiences: %w[admin])

      expect(checks(page).required_field_errors).to include(
        message(:required_field_missing, field: "Email", audience: audience("admin"))
      )
    end

    it "skips identity fields in reference and audience attribute checks" do
      dropdown = { "options_source" => "entity_entries", "entity_id" => student.id, "label_field" => "name" }
      page = form(course, [
        input("title"),
        identity_input("email", html_type: "select", dynamic_options: dropdown, label: "Email")
      ], audiences: %w[admin public])

      expect(checks(page).reference_errors).to eq([])
      expect(checks(page).audience_errors).not_to include(
        message(:reference_private_for_audience, field: "Email", target: "Student", audience: audience("public"))
      )
      expect(checks(page).identity_errors).to eq([message(:identity_field_not_person)])
    end
  end

  describe "#action_errors" do
    let(:student) { define("Student", [attribute("full_name", "姓名")]) }

    it "refuses a second live page for the same action and audience in one tenant" do
      form(student, [input("full_name")], audiences: %w[member], action_key: "enroll", launched: true)
      rival = form(student, [input("full_name")], audiences: %w[member], action_key: "enroll")

      expect(checks(rival).action_errors).to eq([
        message(:action_audience_taken, audience: audience("member"), action: "enroll")
      ])
      expect(rival.launch_errors).to include(message(:action_audience_taken, audience: audience("member"), action: "enroll"))
      expect { rival.launch! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "allows the same key in another tenant or on a shared page" do
      create(:page, :shared, :launched, :member_only, action_key: "enroll")
      create(:page, :launched, :member_only, customer: other_customer, action_key: "enroll")

      page = form(student, [input("full_name")], audiences: %w[member], action_key: "enroll")
      expect(checks(page).action_errors).to eq([])
      page.launch!
      expect(page.reload.launched).to be(true)
    end

    it "frees the slot when the live page is taken offline" do
      live = form(student, [input("full_name")], audiences: %w[member], action_key: "enroll", launched: true)
      live.take_offline!
      successor = form(student, [input("full_name")], audiences: %w[member], action_key: "enroll")

      expect(checks(successor).action_errors).to eq([])
      successor.launch!
      expect(successor.reload.launched).to be(true)
    end
  end

  it "never names the flowchart in a tenant-facing launch message" do
    keys = %w[
      reference_label_hidden reference_target_inactive required_field_missing required_link_field_missing
      owned_entity_public_audience reference_private_for_audience
      bridge_page_member_only action_audience_taken identity_field_not_person
      submission_process_missing submission_process_offline submission_process_incompatible
    ]
    %i[en zh-CN].product(keys).each do |locale, key|
      expect(I18n.t("maint_core.errors.page_launch.#{key}", locale: locale, entity: "E", field: "F",
                                                             label: "L", target: "T", audience: "A", action: "K",
                                                             details: "D")).not_to match(/flowchart|流程图/i)
    end
  end

  describe "#processing_errors" do
    let(:student) { define("Student", [attribute("full_name", "姓名")]) }

    it "blocks launch when the page has no submission process" do
      page = form(student, [input("full_name")])
      page.update_column(:flowchart_id, nil)

      expect(checks(page.reload).processing_errors).to eq([message(:submission_process_missing)])
      expect(page.launch_errors).to include(message(:submission_process_missing))
    end

    it "blocks launch when the bound process is offline" do
      page = form(student, [input("full_name")])
      draft = create(:flowchart, :draft, customer: customer)
      page.update_column(:flowchart_id, draft.id)

      expect(checks(page.reload).processing_errors).to eq([message(:submission_process_offline)])
    end

    it "blocks launch when the bound process names an attribute the entity does not have" do
      page = form(student, [input("full_name")])
      bind_page_flowchart(page, steps: [{
        "action" => "set_record_fields",
        "config" => { "assignments" => [{ "key" => "no_such_field", "value" => "1" }] }
      }])

      errors = checks(page.reload).processing_errors
      expect(errors.size).to eq(1)
      expect(errors.first).to include(student.display_label)
      expect(errors.first).to eq(message(:submission_process_incompatible, entity: student.display_label))
      expect(errors.first).not_to match(/flowchart/i)
    end
  end

  describe "on Page" do
    let(:student) { define("Student", [attribute("full_name", "姓名", validators: required), attribute("motto", "Motto")]) }

    it "adds the checks to launch_errors and refuses to launch" do
      page = form(student, [input("motto")])
      blockers = [message(:required_field_missing, field: "姓名", audience: audience("admin"))]

      expect(page.submission_blockers).to eq(blockers)
      expect(page.launch_errors).to include(*blockers)
      expect { page.launch! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Page.find(page.id).launched).to be(false)
    end

    it "adds audience ownership checks to launch_errors" do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      learner = define("Learner", [attribute("name", "Name")], extended_model: person_model)
      owned = define("Homework", [
        attribute("title", "Title"),
        person_ref("student", "Student", learner, owner: true)
      ], display_label: "Homework")
      page = form(owned, [input("title")], audiences: %w[admin member public])

      expect(page.launch_errors).to include(message(:owned_entity_public_audience, entity: "Homework"))
      expect(page.submission_blockers).not_to include(message(:owned_entity_public_audience, entity: "Homework"))
      expect { page.launch! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "is out of date only when built from a version other than the tenant's head" do
      page = form(student, [input("full_name"), input("motto")])
      expect(page.entity_out_of_date?).to be(false)

      page.update_column(:entity_version_id, student.current_version_id)
      expect(Page.find(page.id).entity_out_of_date?).to be(false)

      student.property_schema_json = student.property_schema_json + [attribute("email", "Email")]
      student.save!(validate: false)
      expect(Page.find(page.id).entity_out_of_date?).to be(true)
    end
  end
end
