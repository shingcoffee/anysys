# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public page ownership at the submit boundary", type: :request do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:member) { create(:user, :member, customer: customer) }
  let(:other_member) { create(:user, :member, customer: customer) }
  let(:admin) { create(:user, :admin, customer: customer) }

  let(:student) { Entity.find_by!(customer_id: customer.id, name: "Student") }
  let(:teacher) { Entity.find_by!(customer_id: customer.id, name: "Teacher") }
  let(:course) { Entity.find_by!(customer_id: customer.id, name: "Course") }
  let(:enrollment) { Entity.find_by!(customer_id: customer.id, name: "Enrollment") }
  let(:assignment) { Entity.find_by!(customer_id: customer.id, name: "Assignment") }

  before do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)

    name_field = [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json
    create(:entity, customer: customer, name: "Student", extended_model: person_model, property_schema: name_field)
    create(:entity, customer: customer, name: "Teacher", extended_model: person_model, property_schema: name_field)
    create(:entity, customer: customer, name: "Course",
           property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    create(:entity, customer: customer, name: "Enrollment", category: :bridge, property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id },
      { "name" => "Course", "name_slug" => "course", "type" => "EntityReference", "entity_id" => course.id }
    ].to_json)
    student.update!(associations: [{
      "target_entity_id" => course.id, "target_entity_name" => course.name,
      "bridge_entity_id" => enrollment.id, "bridge_entity_name" => enrollment.name,
      "display_field" => "title", "display_field_label" => "Title"
    }].to_json)

    create(:entity, customer: customer, name: "Assignment", property_schema: [
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
      person_select("student", student, owner: true),
      person_select("mentor", teacher, name: "Mentor")
    ].to_json)
  end

  describe "member submissions" do
    let!(:own_student) { create(:entity_entry, entity: student, customer: customer, user: member) }
    let!(:peer_student) { create(:entity_entry, entity: student, customer: customer, user: other_member) }
    let!(:own_teacher) { create(:entity_entry, entity: teacher, customer: customer, user: member) }
    let!(:peer_teacher) { create(:entity_entry, entity: teacher, customer: customer, user: other_member) }
    let!(:own_course) do
      create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "Maths" })
    end

    it "drops a forged owner id and stores the member's linked Student" do
      page = build_page(assignment, :for_member)
      sign_in member

      expect {
        post page_url(page), params: { entity: { title: "Essay", student: peer_student.id.to_s } }
      }.to change(EntityEntry, :count).by(1)

      expect(response).to redirect_to("/#{customer.id}/member/pages/#{page.id}")
      saved = EntityEntry.where(customer_id: customer.id, entity_id: assignment.id).order(:id).last
      expect(saved.data_json).to include("student" => own_student.id.to_s, "title" => "Essay")
    end

    it "binds the owner on an owned Enrollment primary" do
      page = build_page(enrollment, :for_member)
      sign_in member

      expect {
        post page_url(page), params: { entity: { student: peer_student.id.to_s, course: own_course.id.to_s } }
      }.to change(EntityEntry, :count).by(1)

      saved = EntityEntry.where(customer_id: customer.id, entity_id: enrollment.id).order(:id).last
      expect(saved.data_json).to include("student" => own_student.id.to_s, "course" => own_course.id.to_s)
    end

    it "rejects a member with no linked Student and writes nothing" do
      unlinkable = create(:user, :member, customer: customer)
      page = build_page(assignment, :for_member)
      sign_in unlinkable

      expect {
        post page_url(page), params: { entity: { title: "Essay", student: peer_student.id.to_s } }
      }.not_to change(EntityEntry, :count)

      expect(response).to redirect_to("/#{customer.id}/member/pages/#{page.id}")
      expect(flash[:alert]).to eq(
        I18n.t("common.errors.dynamic.profile_required", entity: student.display_label)
      )
    end

    it "rejects a mentor outside the member's scope and writes nothing" do
      page = build_page(assignment, :for_member)
      sign_in member

      expect {
        post page_url(page), params: { entity: { title: "Essay", mentor: peer_teacher.id.to_s } }
      }.not_to change(EntityEntry, :count)

      expect(flash[:alert]).to eq(
        I18n.t("common.errors.dynamic.reference_not_allowed", field: "Mentor")
      )
    end

    it "rejects a forged person id from another tenant and writes nothing" do
      foreign_teacher = create(:entity, customer: other_customer, name: "Teacher", extended_model: person_model)
      foreign_entry = create(:entity_entry, entity: foreign_teacher, customer: other_customer)
      page = build_page(assignment, :for_member)
      sign_in member

      expect {
        post page_url(page), params: { entity: { title: "Essay", mentor: foreign_entry.id.to_s } }
      }.not_to change(EntityEntry, :count)

      expect(flash[:alert]).to eq(
        I18n.t("common.errors.dynamic.reference_not_allowed", field: "Mentor")
      )
    end
  end

  describe "public submissions" do
    let!(:own_student) { create(:entity_entry, entity: student, customer: customer) }
    let!(:own_course) do
      create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "Maths" })
    end
    let!(:own_teacher) { create(:entity_entry, entity: teacher, customer: customer) }

    it "rejects a public submit on an owned entity and writes nothing" do
      page = build_page(assignment, :for_member, :for_public)

      expect {
        post page_url(page), params: { entity: { title: "Essay" } }
      }.not_to change(EntityEntry, :count)

      expect(response).to redirect_to(page_url(page))
      expect(flash[:alert]).to eq(I18n.t("common.errors.dynamic.sign_in_required"))
    end

    it "rejects a filled owned Enrollment section on a public Student page" do
      page = build_page(student, :for_member, :for_public, extra_fields: [
        { "id" => "name", "property_slug" => "name", "html_type" => "text" },
        { "id" => "course", "property_slug" => "course", "html_type" => "select",
          "source" => "bridge", "source_section" => enrollment.name }
      ])

      expect {
        post page_url(page), params: {
          entity: { name: "Ada" },
          assoc: { enrollment: { course: own_course.id.to_s } }
        }
      }.not_to change(EntityEntry, :count)

      expect(flash[:alert]).to eq(I18n.t("common.errors.dynamic.sign_in_required"))
    end

    it "saves the public Student primary when the Enrollment section is empty" do
      page = build_page(student, :for_member, :for_public, extra_fields: [
        { "id" => "name", "property_slug" => "name", "html_type" => "text" },
        { "id" => "course", "property_slug" => "course", "html_type" => "select",
          "source" => "bridge", "source_section" => enrollment.name }
      ])

      expect {
        post page_url(page), params: {
          entity: { name: "Ada" },
          assoc: { enrollment: { course: "" } }
        }
      }.to change(EntityEntry, :count).by(1)

      saved = EntityEntry.where(customer_id: customer.id, entity_id: student.id).order(:id).last
      expect(saved.data_json).to include("name" => "Ada")
      expect(EntityEntry.where(customer_id: customer.id, entity_id: enrollment.id)).to be_empty
    end

    it "rejects a filled person reference on a public Student page and writes nothing" do
      student.property_schema_json = [
        { "name" => "Name", "name_slug" => "name", "html_type" => "text" },
        person_select("mentor", teacher, name: "Mentor")
      ]
      student.save!
      page = build_page(student, :for_member, :for_public)

      expect {
        post page_url(page), params: { entity: { name: "Ada", mentor: own_teacher.id.to_s } }
      }.not_to change(EntityEntry, :count)

      expect(flash[:alert]).to eq(
        I18n.t("common.errors.dynamic.reference_not_allowed", field: "Mentor")
      )
    end
  end

  describe "module handoff" do
    let!(:own_student) { create(:entity_entry, entity: student, customer: customer, user: member) }
    let!(:peer_student) { create(:entity_entry, entity: student, customer: customer, user: other_member) }
    let!(:own_course) do
      create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "Maths" })
    end
    let(:feature_module) { create(:feature_module, :handoffable, key: "ownership_demo") }

    before do
      registration = Class.new(FeatureModules::BaseModule) do
        def self.module_key = "ownership_demo"
        def self.module_name = "Ownership demo"
        def self.provision!(_customer) = nil
        entry_path { |tenant| "/#{tenant.id}/ownership-demo" }
        input_contract do
          property :owner
          property :enrolled_student
        end
      end
      create(:customer_feature_module, customer: customer, feature_module: feature_module)
      allow_any_instance_of(FeatureModules::Module).to receive(:registration_class).and_wrap_original do |original|
        original.receiver.key == feature_module.key ? registration : original.call
      end
    end

    def with_handoff(page, input_rows)
      bind_page_flowchart(page, steps: [{
        "action" => "hand_off_to_module",
        "config" => { "moduleKey" => feature_module.key, "input" => input_rows }
      }])
      page
    end

    it "hands the member's own Student to the module, not a forged owner id" do
      page = with_handoff(build_page(assignment, :for_member),
                          [{ "key" => "owner", "value" => "ctx[:params]['student']" }])
      sign_in member

      post page_url(page), params: { entity: { title: "Essay", student: peer_student.id.to_s } }

      expect(session[:feature_module_invocation][:input][:owner]).to eq(own_student.id.to_s)
    end

    it "never hands a forged Enrollment back-reference to the module" do
      page = build_page(student, :for_member, extra_fields: [
        { "id" => "name", "property_slug" => "name", "html_type" => "text" },
        { "id" => "course", "property_slug" => "course", "html_type" => "select",
          "source" => "bridge", "source_section" => enrollment.name }
      ])
      with_handoff(page, [{ "key" => "enrolled_student",
                            "value" => "ctx[:association_params].to_h.dig('enrollment', 'student')" }])
      sign_in member

      post page_url(page), params: {
        entity: { name: "Ada" },
        assoc: { enrollment: { course: own_course.id.to_s, student: peer_student.id.to_s } }
      }

      expect(session[:feature_module_invocation][:input][:enrolled_student]).to be_nil
      saved = EntityEntry.where(customer_id: customer.id, entity_id: enrollment.id).order(:id).last
      expect(saved.data_json["student"]).not_to eq(peer_student.id.to_s)
    end
  end

  describe "admin submissions" do
    let!(:peer_student) { create(:entity_entry, entity: student, customer: customer) }
    let!(:peer_teacher) { create(:entity_entry, entity: teacher, customer: customer, user: other_member) }

    it "does not bind the owner or extra-check references" do
      page = build_page(assignment, :for_member, :for_public)
      sign_in admin

      expect {
        post page_url(page), params: { entity: { title: "Essay", student: peer_student.id.to_s, mentor: peer_teacher.id.to_s } }
      }.to change(EntityEntry, :count).by(1)

      saved = EntityEntry.where(customer_id: customer.id, entity_id: assignment.id).order(:id).last
      expect(saved.data_json).to include(
        "title" => "Essay", "student" => peer_student.id.to_s, "mentor" => peer_teacher.id.to_s
      )
    end
  end

  def page_url(page)
    "/#{customer.id}/page/#{page.public_uuid}"
  end

  def build_page(entity, *traits, extra_fields: nil)
    traits = %i[for_member] if traits.empty?
    fields = extra_fields || Array(entity.property_schema_json).map do |attribute|
      { "id" => attribute["name_slug"], "property_slug" => attribute["name_slug"],
        "html_type" => attribute["html_type"] || "text" }
    end
    Current.set(customer: customer) do
      create(:page, *traits, customer: customer, entity: entity, launched: true,
                    configuration: {
                      form_settings: {},
                      metadata: { entity_id: entity.id, entity_name: entity.name },
                      pages: [{ "id" => "page_1", "fields" => fields }]
                    }.to_json)
    end
  end

  def person_select(slug, target, owner: false, name: nil)
    attribute = {
      "name" => name || slug.capitalize,
      "name_slug" => slug,
      "html_type" => "select",
      "config" => {
        "options_source" => "entity_entries",
        "entity_id" => target.id.to_s,
        "label_field" => "name"
      }
    }
    attribute["owner"] = true if owner
    attribute
  end
end
