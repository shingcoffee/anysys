# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::MemberRows do
  let(:customer) { create(:customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:member) { create(:user, :member, customer: customer) }
  let(:other_member) { create(:user, :member, customer: customer) }

  def reference(name, entity) = { "name" => name.capitalize, "name_slug" => name, "html_type" => "select", "type" => "EntityReference", "entity_id" => entity.id.to_s }

  let(:student_entity) do
    create(:entity, customer: customer, name: "Student", extended_model: person_model,
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
  end
  let(:course_entity) do
    create(:entity, customer: customer, name: "Course", property_schema: [{ "name" => "Code", "name_slug" => "code", "html_type" => "text" }].to_json)
  end
  let(:order_entity) { create(:entity, customer: customer, name: "Order", property_schema: [reference("student", student_entity)].to_json) }
  let(:line_entity) do
    create(:entity, customer: customer, name: "Line",
                    property_schema: [reference("order", order_entity), reference("course", course_entity),
                                      { "name" => "Quantity", "name_slug" => "quantity", "html_type" => "number" }].to_json)
  end

  before { enable_module!("authentication", customer).set_extendable_model!(person_model, true) }

  let(:own_student) { create(:entity_entry, entity: student_entity, customer: customer, user: member) }
  let(:peer_student) { create(:entity_entry, entity: student_entity, customer: customer, user: other_member) }
  let(:math) { create(:entity_entry, :with_data, customer: customer, entity: course_entity, entry_data: { "code" => "MATH-101" }) }
  let(:own_order) { create(:entity_entry, :with_data, customer: customer, entity: order_entity, entry_data: { "student" => own_student.id.to_s }) }
  let(:peer_order) { create(:entity_entry, :with_data, customer: customer, entity: order_entity, entry_data: { "student" => peer_student.id.to_s }) }

  def line(order) = create(:entity_entry, :with_data, customer: customer, entity: line_entity, entry_data: { "order" => order.id.to_s, "course" => math.id.to_s })

  def page_for(entity, inputs: [{ "field" => "order", "entity_id" => order_entity.id.to_s }], manage_rows: true, **attributes)
    config = { form_settings: { modes: %w[create update], inputs: inputs, manage_rows: manage_rows }, pages: [{ id: "page_1", fields: [] }] }
    Current.set(customer: customer) do
      create(:page, :member_only, customer: customer, entity: entity, launched: true, configuration: config.to_json, **attributes)
    end
  end

  let(:page) { page_for(line_entity) }

  describe ".managing?" do
    it "is a launched member page managing the rows of a record the member reaches through its one input" do
      expect(described_class.managing?(page)).to be(true)
    end

    it "is not a page that leaves rows alone, is offline, or is not for members" do
      expect(described_class.managing?(page_for(line_entity, manage_rows: false))).to be(false)
      expect(described_class.managing?(page_for(line_entity, launched: false))).to be(false)
      expect(described_class.managing?(page_for(line_entity, audience_member: false, audience_admin: true))).to be(false)
    end

    it "is not a page without exactly one input, or whose rows every member reaches" do
      review_entity = create(:entity, customer: customer, name: "Review", property_schema: [reference("course", course_entity)].to_json)

      expect(described_class.managing?(page_for(line_entity, inputs: []))).to be(false)
      expect(described_class.managing?(page_for(review_entity, inputs: [{ "field" => "course", "entity_id" => course_entity.id.to_s }]))).to be(false)
    end
  end

  describe ".page_for" do
    it "finds the page managing the entity's rows from that record type" do
      page
      page_for(line_entity, manage_rows: false)

      expect(described_class.page_for(entity: line_entity, parent_entity_id: order_entity.id, customer_id: customer.id)).to eq(page)
      expect(described_class.page_for(entity: line_entity, parent_entity_id: course_entity.id, customer_id: customer.id)).to be_nil
    end
  end

  describe ".record" do
    def record(id, viewer: member) = described_class.record(page: page, record_id: id, viewer: viewer, customer_id: customer.id)

    it "is the member's own record of the input's type" do
      expect(record(own_order.id.to_s)).to eq(own_order)
    end

    it "is nothing for another member's record, another type, another tenant or a malformed id" do
      foreign = create(:entity_entry, customer: create(:customer), entity: order_entity)

      [peer_order.id, math.id, foreign.id, "abc", "0", "", nil].each { |id| expect(record(id.to_s)).to be_nil }
      expect(record(own_order.id.to_s, viewer: other_member)).to be_nil
    end
  end

  describe ".row" do
    def row(id) = described_class.row(page: page, entry_id: id.to_s, viewer: member, customer_id: customer.id)

    it "is a row hanging off the member's own record" do
      own_line = line(own_order)
      expect(row(own_line.id).id).to eq(own_line.id)
      expect(described_class.record_of(page: page, row: own_line, viewer: member, customer_id: customer.id)).to eq(own_order)
    end

    it "is nothing for another member's row, a row of another entity, or a malformed id" do
      expect(row(line(peer_order).id)).to be_nil
      expect(row(own_order.id)).to be_nil
      expect(row("x")).to be_nil
    end

    it "is nothing on a page that does not manage rows" do
      own_line = line(own_order)
      expect(described_class.row(page: page_for(line_entity, manage_rows: false), entry_id: own_line.id.to_s,
                                 viewer: member, customer_id: customer.id)).to be_nil
    end
  end
end
