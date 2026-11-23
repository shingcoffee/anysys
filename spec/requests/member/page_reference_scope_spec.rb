# frozen_string_literal: true

require "rails_helper"

# GET /:cid/member/pages/:id — reference dropdowns are row-scoped.
RSpec.describe "Member page reference scope", type: :request do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:member) { create(:user, :member, customer: customer) }
  let(:peer) { create(:user, :member, customer: customer) }
  let(:foreign_member) { create(:user, :member, customer: other_customer) }
  let(:admin) { create(:user, :admin, customer: customer) }

  let!(:student) do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    create(:entity, customer: customer, name: "Student", extended_model: person_model,
           property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
  end
  let!(:course) do
    create(:entity, customer: customer, name: "Course",
           property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
  end
  let!(:teacher) do
    create(:entity, customer: customer, name: "Teacher", extended_model: person_model,
           property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
  end
  # Student is a person-ref on the bound entity but not the owner, so the
  # dropdown still renders for members.
  let!(:form_entity) do
    create(:entity, customer: customer, name: "Assignment", property_schema: [
      { "name" => "Student", "name_slug" => "student", "html_type" => "select",
        "config" => { "options_source" => "entity_entries", "entity_id" => student.id.to_s, "label_field" => "name" } },
      { "name" => "Teacher", "name_slug" => "teacher", "html_type" => "select", "owner" => true,
        "config" => { "options_source" => "entity_entries", "entity_id" => teacher.id.to_s, "label_field" => "name" } },
      { "name" => "Course", "name_slug" => "course", "html_type" => "select",
        "config" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s, "label_field" => "title" } }
    ].to_json)
  end

  let!(:own_student) { create(:entity_entry, customer: customer, entity: student, user: member, data: { name: "Ada" }.to_json) }
  let!(:peer_student) { create(:entity_entry, customer: customer, entity: student, user: peer, data: { name: "Grace" }.to_json) }
  let!(:own_course) { create(:entity_entry, customer: customer, entity: course, data: { title: "Algebra" }.to_json) }
  let!(:peer_course) { create(:entity_entry, customer: customer, entity: course, data: { title: "Biology" }.to_json) }

  let!(:foreign_student) do
    enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)
    foreign_entity = create(:entity, customer: other_customer, name: "Student", extended_model: person_model,
                            property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    create(:entity_entry, customer: other_customer, entity: foreign_entity, user: foreign_member,
           data: { name: "Foreign" }.to_json)
  end

  let!(:page_record) do
    Current.set(customer: customer) do
      create(:page, :for_member, customer: customer, entity: form_entity, launched: true,
             configuration: {
               "pages" => [{
                 "id" => "page_1",
                 "fields" => [
                   { "id" => "student", "property_slug" => "student", "html_type" => "select", "label" => "Student",
                     "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => student.id.to_s,
                                            "label_field" => "name" } },
                   { "id" => "course", "property_slug" => "course", "html_type" => "select", "label" => "Course",
                     "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s,
                                            "label_field" => "title" } }
                 ]
               }],
               "metadata" => { "entity_id" => form_entity.id }
             }.to_json)
    end
  end

  def show_url(cid = customer.id, page_id = page_record.id)
    "/#{cid}/member/pages/#{page_id}"
  end

  def field_node(slug)
    document = Nokogiri::HTML(response.body)
    field = document.at_css(%([data-field-id="#{slug}"]))
    expect(field).to be_present, "expected a rendered field #{slug}, got status #{response.status}"
    field
  end

  def option_values(slug)
    field_node(slug).css('option:not([value=""])').map { |option| option["value"] }
  end

  def option_labels(slug)
    field_node(slug).css('option:not([value=""])').map { |option| option.text.strip }
  end

  it "lists only the member's Student and every Course" do
    sign_in member
    get show_url

    expect(response).to have_http_status(:ok)
    expect(option_values("student")).to eq([own_student.id.to_s])
    expect(option_labels("student")).to eq(["Ada"])
    expect(option_values("student")).not_to include(peer_student.id.to_s, foreign_student.id.to_s)
    expect(option_values("course")).to match_array([own_course.id.to_s, peer_course.id.to_s])
    expect(option_labels("course")).to match_array(%w[Algebra Biology])
  end

  it "does not list another same-tenant member's Student" do
    sign_in peer
    get show_url

    expect(response).to have_http_status(:ok)
    expect(option_values("student")).to eq([peer_student.id.to_s])
    expect(option_values("student")).not_to include(own_student.id.to_s)
    expect(option_values("course")).to match_array([own_course.id.to_s, peer_course.id.to_s])
  end

  it "denies a member of another tenant" do
    sign_in foreign_member
    get show_url

    expect(response).not_to have_http_status(:ok)
    expect(response.body).not_to include("Ada", "Grace", "Foreign")
  end

  it "lists every tenant Student on the admin entry form (regression)" do
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: form_entity, launched: true, configuration: page_record.configuration)
    end
    sign_in admin
    get new_admin_entity_entry_path(customer.id, form_entity)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    student_values = document.at_css(%([data-field-id="student"])).css('option:not([value=""])').map { |option| option["value"] }
    expect(student_values).to include(own_student.id.to_s, peer_student.id.to_s)
    expect(student_values).not_to include(foreign_student.id.to_s)
  end
end
