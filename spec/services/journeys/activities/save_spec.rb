# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::Activities::Save do
  let(:customer) { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:domain) { create(:entity_domain, customer: customer) }

  include_context "student course association"

  let!(:start_page) { Current.set(customer: customer) { create(:page, customer: customer, entity: student_entity, name: "Student New") } }
  let!(:relate_page) do
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: bridge_entity, name: "Add course", action_key: "student_add_course",
                    configuration: { form_settings: { inputs: [{ field: "student", entity_id: student_entity.id }] },
                                     pages: [{ id: "page_1", fields: [] }] }.to_json)
    end
  end

  let(:rows) do
    [
      { "key" => "start", "page_id" => start_page.id.to_s },
      { "key" => "relate_1", "page_id" => relate_page.id.to_s, "inputs" => { "student" => "start" }, "repeat" => "1" },
      { "key" => "finish", "finish_kind" => "record", "finish_step" => "start" }
    ]
  end

  def save(journey = Journey.new, customer_id: customer.id, **params)
    defaults = { "name" => " Enrolment ", "key" => "enrolment", "description" => "", "entity_domain_id" => domain.id.to_s,
                 "visible_audiences" => %w[admin member], "steps" => rows }
    described_class.call(journey: journey, params: defaults.merge(params.stringify_keys), customer_id: customer_id)
  end

  it "creates a journey and gives an unkeyed page an action key" do
    result = save

    expect(result.ok).to be(true)
    expect(result.errors).to eq([])
    journey = result.journey.reload
    expect(journey).to have_attributes(customer_id: customer.id, name: "Enrolment", key: "enrolment", description: nil,
                                       entity_domain_id: domain.id, visible_audiences: %w[admin member])
    expect(journey).to be_draft
    expect(start_page.reload.action_key).to eq("student_new_#{start_page.id}")
    definition = journey.steps_definition
    expect(definition).to be_valid
    expect(definition.action_keys).to eq(["student_new_#{start_page.id}", "student_add_course"])
    expect(definition.step("relate_1")).to have_attributes(inputs: { "student" => "start" }, repeat: true)
  end

  it "updates an existing journey, keeping its steps when none are submitted" do
    journey = create(:journey, customer: customer, key: "enrolment")

    result = described_class.call(journey: journey, params: { "name" => "Renamed", "key" => "enrolment", "entity_domain_id" => domain.id.to_s },
                                  customer_id: customer.id)

    expect(result.ok).to be(true)
    expect(journey.reload).to have_attributes(name: "Renamed", entity_domain_id: domain.id, visible_audiences: %w[admin])
    expect(journey.steps_definition.action_keys).to eq(%w[student_new student_add_course])
  end

  it "requires a domain" do
    result = save(entity_domain_id: "")

    expect(result.ok).to be(false)
    expect(result.errors).to include(a_string_including(I18n.t("maint_core.entity_domains.errors.domain_required")))
    expect(Journey.count).to eq(0)
  end

  it "rejects a domain from another tenant" do
    foreign_domain = create(:entity_domain, customer: other_customer)

    result = save(entity_domain_id: foreign_domain.id.to_s)

    expect(result.ok).to be(false)
    expect(result.errors).to include(a_string_including(I18n.t("maint_core.entity_domains.errors.domain_unavailable")))
    expect(Journey.count).to eq(0)
  end

  it "returns definition errors and writes nothing, not even a page key" do
    broken = rows.dup.tap { |list| list[1] = list[1].merge("inputs" => { "student" => "finish" }) }

    result = save(steps: broken)

    expect(result.ok).to be(false)
    expect(result.errors).to include(I18n.t("journeys.definition.errors.input_source_invalid", step: "relate_1"))
    expect(result.journey).to be_new_record
    expect(Journey.count).to eq(0)
    expect(start_page.reload.action_key).to be_nil
  end

  it "rejects a taken key, a blank name and no audience" do
    create(:journey, customer: customer, key: "enrolment")

    result = save(name: " ", visible_audiences: [""])

    expect(result.ok).to be(false)
    expect(result.errors).to include(a_string_including(I18n.t("errors.messages.taken")),
                                     a_string_including(I18n.t("errors.messages.blank")),
                                     I18n.t("journeys.launch.errors.audiences_blank"))
    expect(Journey.count).to eq(1)
    expect(start_page.reload.action_key).to be_nil
  end

  it "refuses a journey that belongs to another tenant" do
    journey = create(:journey, customer: other_customer, name: "Theirs")

    result = save(journey)

    expect(result.ok).to be(false)
    expect(result.errors).to eq([I18n.t("journeys.admin.errors.invalid_customer")])
    expect(journey.reload.name).to eq("Theirs")
  end

  describe "a launched journey" do
    let(:journey) do
      create(:journey, :launched, customer: customer, key: "enrolment", name: "Live",
                                  definition: { "steps" => [
                                    { "key" => "start", "kind" => "create", "action_key" => "student_new" },
                                    { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
                                  ] }.to_json)
    end

    before do
      Current.set(customer: customer) do
        start_page.update!(action_key: "student_new", launched: true,
                           configuration: start_page.configuration_json.merge("form_settings" => { "modes" => %w[create] }).to_json)
        relate_page.update!(launched: true)
      end
    end

    it "saves when the launch checks still pass" do
      result = save(journey, visible_audiences: %w[admin])

      expect(result.ok).to be(true)
      expect(journey.reload).to have_attributes(name: "Enrolment", status: "launched")
    end

    it "refuses changes that would break the live journey and keeps the stored one" do
      result = save(journey, visible_audiences: %w[admin member])

      expect(result.ok).to be(false)
      expect(result.errors).to include(I18n.t("journeys.launch.errors.page_missing", step: "start",
                                                                                     audience: I18n.t("journeys.audiences.member")))
      expect(journey.reload).to have_attributes(name: "Live", visible_audiences: %w[admin])
      expect(journey.steps_definition.steps.size).to eq(2)
    end

    it "does not run the launch checks for a draft" do
      journey.update!(status: :draft)

      expect(save(journey, visible_audiences: %w[admin member]).ok).to be(true)
    end
  end

  it "refuses an unknown customer" do
    expect(save(customer_id: "abc").ok).to be(false)
    expect(save(customer_id: Customer.maximum(:id).to_i + 1).ok).to be(false)
    expect(Journey.count).to eq(0)
  end
end
