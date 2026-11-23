# frozen_string_literal: true

require "rails_helper"

# A generated member journey: a signed-in member places an order they own,
# then adds its lines on a member page with the order locked in.
RSpec.describe "Member journey adding the rows of a record they own", type: :request do
  let(:customer) { create(:customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:member) { create(:user, :member, customer: customer) }
  let(:other_member) { create(:user, :member, customer: customer) }

  let(:student_entity) do
    create(:entity, customer: customer, name: "Student", display_label: "Student", extended_model: person_model,
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
  end
  let(:course_entity) do
    create(:entity, customer: customer, name: "Course", display_label: "Course",
                    property_schema: [{ "name" => "Code", "name_slug" => "code", "html_type" => "text" }].to_json)
  end
  let(:order_entity) do
    create(:entity, customer: customer, name: "Order", display_label: "Order", property_schema: [
      { "name" => "Student", "name_slug" => "student", "html_type" => "select", "type" => "EntityReference",
        "entity_id" => student_entity.id.to_s, "validators" => [{ "type" => "presence" }] },
      { "name" => "Number", "name_slug" => "number", "html_type" => "text" }
    ].to_json)
  end
  let(:line_entity) { Entity.find_by!(customer_id: customer.id, name: "assoc_order_course") }

  before { enable_module!("authentication", customer).set_extendable_model!(person_model, true) }

  let!(:own_student) { create(:entity_entry, entity: student_entity, customer: customer, user: member) }
  let!(:peer_student) { create(:entity_entry, entity: student_entity, customer: customer, user: other_member) }
  let!(:math) { create(:entity_entry, :with_data, customer: customer, entity: course_entity, entry_data: { "code" => "MATH-101" }) }
  let!(:peer_order) do
    create(:entity_entry, :with_data, customer: customer, entity: order_entity,
                                      entry_data: { "student" => peer_student.id.to_s, "number" => "P-1" })
  end
  let!(:journey) do
    order_entity.associations_json = [{ "target_entity_id" => course_entity.id, "target_entity_name" => course_entity.name,
                                        "display_field" => "code", "display_field_label" => "Code",
                                        "additional_attributes" => [{ "name" => "Quantity", "name_slug" => "quantity",
                                                                      "html_type" => "number" }] }]
    order_entity.save!
    order_entity.sync_bridge_entities!
    domain = create(:entity_domain, customer: customer, name: "Shop")
    [student_entity, course_entity, order_entity.reload].each { |entity| EntityDomains::Memberships.place!(entity, domain) }
    generated = Journeys::Activities::Generate.call(customer: customer, domain_id: domain.id, candidate_key: "member-#{order_entity.id}")
    Journeys::Activities::Launch.call(journey: generated.journey)
    generated.journey.reload
  end

  def page(action_key) = Page.find_by!(customer_id: customer.id, action_key: action_key)
  def submit_path(action_key) = "/#{customer.id}/page/#{page(action_key).public_uuid}"
  def lines = EntityEntry.where(customer_id: customer.id, entity_id: line_entity.id)
  def own_orders = EntityEntry.where(customer_id: customer.id, entity_id: order_entity.id).where.not(id: peer_order.id)

  before { sign_in member }

  it "places the member's own order, adds its lines against it, and finishes on the order" do
    expect(journey).to be_launched

    post submit_path("member_new_order"), params: { entity: { number: "A-1", student: peer_student.id.to_s } }
    order = own_orders.sole
    token = Addressable::URI.parse(response.location).query_values["run"]
    expect(order.data_json).to include("student" => own_student.id.to_s, "number" => "A-1")
    expect(response.location).to include("/member/pages/#{page("member_order_add_course").id}")

    follow_redirect!
    body = Nokogiri::HTML(response.body)
    expect(body.at_css("[data-role='locked-inputs']").text).to include("A-1")
    expect(body.at_css("[name='entity[order]']")).to be_nil
    expect(body.at_css("select[name='entity[course]']")).to be_present

    post submit_path("member_order_add_course"),
         params: { _run: token, _intent: "add_another", entity: { course: math.id.to_s, quantity: "2" } }
    expect(lines.sole.data_json).to include("order" => order.id.to_s, "course" => math.id.to_s)
    expect(flash[:notice]).to eq(I18n.t("journeys.runtime.saved_add_another"))

    post submit_path("member_order_add_course"), params: { _run: token, entity: { course: math.id.to_s, quantity: "1" } }
    expect(lines.count).to eq(2)
    expect(response).to redirect_to(member_surface_path(customer.id, "entity_#{order_entity.id}", order.id))
    expect(flash[:notice]).to eq(I18n.t("journeys.runtime.completed"))
  end

  it "tells processing which submit finishes the journey" do
    seen = []
    allow(FlowchartRuntime::PageRun).to receive(:call).and_wrap_original do |original, **kwargs, &handoff|
      seen << kwargs[:context].journey
      original.call(**kwargs, &handoff)
    end

    post submit_path("member_new_order"), params: { entity: { number: "A-1" } }
    token = Addressable::URI.parse(response.location).query_values["run"]
    post submit_path("member_order_add_course"),
         params: { _run: token, _intent: "add_another", entity: { course: math.id.to_s, quantity: "2" } }
    post submit_path("member_order_add_course"), params: { _run: token, entity: { course: math.id.to_s, quantity: "1" } }

    expect(seen.map { |journey| journey.values_at("step", "finishing") })
      .to eq([[journey.steps_definition.steps.first.key, false], ["relate_1", false], ["relate_1", true]])
  end

  it "never adds a line to another member's order: the journey's order wins, and alone the page refuses it" do
    post submit_path("member_new_order"), params: { entity: { number: "A-1" } }
    order = own_orders.sole
    token = Addressable::URI.parse(response.location).query_values["run"]
    forged = { course: math.id.to_s, quantity: "1", order: peer_order.id.to_s }

    post submit_path("member_order_add_course"), params: { _run: token, entity: forged }
    expect(lines.sole.data_json).to include("order" => order.id.to_s)
    expect { post submit_path("member_order_add_course"), params: { entity: forged } }.not_to change(lines, :count)
  end
end
