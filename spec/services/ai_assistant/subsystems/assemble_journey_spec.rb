# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Subsystems::AssembleJourney do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let!(:domain) { create(:entity_domain, customer: customer, name: "Club Venues") }
  let(:raw_flows) { AiAssistant::Subsystems::Flows.schema["examples"].first }
  let(:flows) { AiAssistant::Subsystems::Flows.new(raw_flows) }
  let(:sign_in) { "self_signup" }
  let(:brief) { AiAssistant::Subsystems::Brief.new(venue_brief("people" => [{ "name" => "Member", "audience" => "member", "sign_in" => sign_in }])) }
  let(:statuses) do
    { "source" => "static", "values" => [{ "label" => "Requested", "default" => true }, { "label" => "Approved" },
                                         { "label" => "Declined" }, { "label" => "Paid" }] }
  end
  let(:lifecycle) do
    { "transitions" => [{ "from" => "Requested", "to" => "Approved", "by" => ["admin"] },
                        { "from" => "Requested", "to" => "Declined", "by" => ["admin"] },
                        { "from" => "Approved", "to" => "Paid", "by" => ["system"] }] }
  end
  let(:entities) do
    input = { "domain" => domain.name, "entities" => [
      { "name" => "Member", "extends" => EntityDefinitions::Capabilities::PERSON_MODEL,
        "attributes" => [{ "name" => "Phone", "html_type" => "tel" }] },
      { "name" => "Venue", "attributes" => [{ "name" => "Venue name", "html_type" => "text", "rules" => [{ "type" => "presence" }] }] },
      { "name" => "Booking", "attributes" => [
        { "name" => "Venue", "html_type" => "select", "options" => { "source" => "entity_entries", "entity" => "Venue", "label_field" => "venue_name" },
          "rules" => [{ "type" => "presence" }] },
        { "name" => "Member", "html_type" => "select", "owner" => true,
          "options" => { "source" => "entity_entries", "entity" => "Member", "label_field" => "phone" } },
        { "name" => "Booking date", "html_type" => "date" },
        { "name" => "Number of guests", "html_type" => "number" },
        { "name" => "Review notes", "html_type" => "textarea" },
        { "name" => "Booking status", "html_type" => "select", "options" => statuses, "lifecycle" => lifecycle }
      ] }
    ] }
    ctx = Operations::Context.new(customer: customer, actor: admin, channel: "assistant")
    outcome = Operations::Activities::Execute.call(operation: "create_entity", context: ctx, input: input)
    raise "create_entity refused: #{outcome.violations.map(&:as_json)}" unless outcome.status == "succeeded"

    %w[Member Venue Booking].to_h { |name| [name, { "id" => Entity.find_by!(customer_id: customer.id, name: name).id }] }
  end

  before do
    enable_module!("authentication", customer, name: "Authentication")
      .set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
  end

  def assemble(key, built: {})
    described_class.call(customer: customer, domain: domain, flows: flows, brief: brief, journey: flows.journey(key),
                         entities: entities, built: built).tap { |result| expect(result.errors).to eq([]) }
  end

  def steps(result) = result.journey.steps_definition.steps.to_h { |step| [step.key, step] }
  def page(result, step) = Page.find(result.pages.fetch(step))

  it "leaves the owner reference off a member's page and sends a sign-up on to the member journey" do
    booking = assemble("request_booking")
    signup = assemble("member_signup", built: { "request_booking" => { "first_action_key" => booking.first_action_key } })

    request = page(booking, "booking")
    expect(request.visible_audiences).to eq(["member"])
    expect(request.input_fields.map { |field| field["property_slug"] }).to include("venue", "booking_date", "number_of_guests")
    expect(request.input_fields.map { |field| field["property_slug"] }).not_to include("member", "booking_status", "review_notes")

    expect(page(signup, "member").flowchart).to eq(Flowcharts::SignUpPageFlowchart.for_customer(customer))
    expect(steps(signup).fetch("finish").target).to eq("kind" => "page", "action_key" => booking.first_action_key)
    expect(Journeys::LaunchChecks.new(booking.journey).errors).to eq([])
  end

  it "starts a member's journey from their own approved bookings and edits that record" do
    result = assemble("pay_booking")
    record = steps(result).fetch("record")
    status = Entities::Lifecycle.find(Entity.find(entities["Booking"]["id"]), "booking_status")

    expect(record.kind).to eq("record")
    expect(record.when).to eq("field" => "booking_status", "in" => [status.states.second])
    expect(steps(result).fetch("payment").record).to eq("record")
    expect(page(result, "payment").submission_modes).to eq(%w[update])
    expect(Journeys::LaunchChecks.new(result.journey).errors).to eq([])
  end

  it "keeps the journey's description" do
    expect(assemble("request_booking").journey.description).to eq("Members request a venue for a date; the bookings team is told.")
  end

  context "when an earlier step's processing may leave a later one out" do
    let(:raw_flows) do
      example = AiAssistant::Subsystems::Flows.schema["examples"].first.deep_dup
      review = example["journeys"].find { |journey| journey["key"] == "review_booking" }
      review["steps"] << { "key" => "notes", "kind" => "update", "object" => "Booking", "label" => "Review notes", "edits" => "start",
                           "fields" => ["Review notes"], "skip" => { "by" => "review", "when" => "the booking was declined" } }
      example
    end

    it "marks that step as one processing may skip" do
      result = assemble("review_booking")

      expect(steps(result).fetch("notes")).to be_conditional
      expect(steps(result).fetch("review")).not_to be_conditional
      expect(result.journey.steps_definition).to be_valid
    end
  end

  context "when staff create the people's accounts" do
    let(:sign_in) { "staff_created" }
    let(:raw_flows) do
      example = AiAssistant::Subsystems::Flows.schema["examples"].first.deep_dup
      example["journeys"] = [{ "key" => "add_member", "name" => "Add a member", "audience" => "admin",
                               "steps" => [{ "key" => "member", "kind" => "create", "object" => "Member", "label" => "Member", "fields" => ["Phone"] }] }]
      example
    end

    it "opens with the account the next page's person record is saved for" do
      result = assemble("add_member")

      expect(result.journey.steps_definition.steps.map(&:kind)).to eq(%w[user create finish])
      expect(Journeys::LaunchChecks.new(result.journey).errors).to eq([])
    end
  end

  it "builds nothing when a step's rows have no reference to the record they belong to" do
    raw_flows["journeys"] << { "key" => "add_venues", "name" => "Add venues", "audience" => "admin",
                               "steps" => [{ "key" => "booking", "kind" => "create", "object" => "Booking", "label" => "Booking", "fields" => ["Booking date"] },
                                           { "key" => "venues", "kind" => "add", "object" => "Venue", "label" => "Venues", "parent" => "booking", "fields" => ["Venue name"] }] }
    entities

    expect do
      result = described_class.call(customer: customer, domain: domain, flows: flows, brief: brief, journey: flows.journey("add_venues"),
                                    entities: entities, built: {})
      expect(result.ok).to be(false)
      expect(result.errors).to eq([I18n.t("ai_assistant.subsystems.build.link_missing", name: "Venues")])
    end.not_to change(Page, :count)
  end
end
