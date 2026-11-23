# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Subsystems::Flows do
  let(:brief) { AiAssistant::Subsystems::Brief.new(venue_brief) }

  def check(raw, with_brief: brief) = AiAssistant::Subsystems::FlowCheck.call(flows: AiAssistant::Subsystems::Flows.new(raw), brief: with_brief)

  def walk(node, path, &block)
    return unless node.is_a?(Hash)

    yield node, path
    node.fetch("properties", {}).each { |key, child| walk(child, "#{path}/#{key}", &block) }
    node.fetch("$defs", {}).each { |key, child| walk(child, "#{path}/$defs/#{key}", &block) }
    walk(node["items"], "#{path}/items", &block)
  end

  describe "the schema" do
    it "documents every position and enum value, and closes every object" do
      problems = []
      walk(described_class.schema, "#") do |node, path|
        problems << "#{path} has no description" if node["description"].blank?
        problems << "#{path} is open" if node["type"] == "object" && node["additionalProperties"] != false
        Array(node["enum"]).each { |value| problems << "#{path} #{value} undescribed" unless node.dig("x-enum-descriptions", value) }
      end

      expect(problems).to eq([])
    end

    it "accepts its own example, which passes every flow check" do
      example = described_class.schema["examples"].first
      people = [{ "name" => "Member", "audience" => "member", "sign_in" => "self_signup" }]

      expect(described_class.schema_errors(example)).to eq([])
      expect(check(example, with_brief: AiAssistant::Subsystems::Brief.new(venue_brief("people" => people)))).to eq([])
    end

    it "reports schema errors by pointer" do
      expect(described_class.schema_errors({ "objects" => [] })).to include(a_string_starting_with("/objects:"), a_string_starting_with("/:"))
    end
  end

  describe AiAssistant::Subsystems::FlowCheck do
    it "passes the venue flows" do
      expect(check(venue_flows)).to eq([])
    end

    it "catches unknown objects and states, misplaced steps and wrong sources" do
      flows = venue_flows.deep_dup
      record, review = flows["journeys"]
      record["steps"].first["kind"] = "update"
      record["steps"].second.merge!("parent" => "nowhere", "object" => "Ticket")
      review["start"]["status_in"] = ["Pending"]
      review["steps"].first.merge!("status_choices" => %w[Approved Closed], "optional" => true)

      expect(check(flows)).to include(
        "Journey record_booking step booking: a journey without a start record begins with a create step.",
        "Journey record_booking step booking: update steps need edits.",
        "Journey record_booking step guests: object Ticket is not in objects.",
        "Journey review_booking: Pending is not a state of Booking.",
        "Journey review_booking step review: the first step can't be optional.",
        "Journey review_booking step review: Closed is not a state of Booking."
      )
    end

    it "requires picked states to come with the status field, and the other way round" do
      flows = venue_flows.deep_dup
      flows["journeys"].second["steps"].first["fields"] = ["Notes"]

      expect(check(flows)).to eq(["Journey review_booking step review: status_choices need the status field in fields."])
    end

    it "ends a journey at a step that takes a payment" do
      flows = venue_flows.deep_dup
      flows["journeys"].first["steps"].first["paid_status"] = "Approved"

      expect(check(flows)).to eq(["Journey record_booking step booking: a step that takes a payment ends its journey."])
    end

    it "keeps member and public journeys to people who sign in" do
      flows = venue_flows.deep_dup
      flows["journeys"].first["audience"] = "member"
      flows["journeys"] << { "key" => "join", "name" => "Join", "audience" => "public", "continues_to" => "review_booking",
                             "steps" => [{ "key" => "me", "kind" => "create", "object" => "Venue", "label" => "Me", "fields" => ["Name"] }] }

      expect(check(flows)).to include(
        "Journey record_booking: member journeys need people who sign in; the brief says they never do.",
        "Journey record_booking: member journeys need a person object.",
        "Journey join: public journeys only sign people up, so the brief must allow sign-up.",
        "Journey join: a public journey's first step creates the person object.",
        "Journey join: continues_to review_booking is not a member journey."
      )
    end

    it "rejects duplicate keys and reserved step keys" do
      flows = venue_flows.deep_dup
      flows["journeys"] << flows["journeys"].first.deep_dup
      flows["journeys"].second["steps"].first["key"] = "finish"

      expect(check(flows)).to include("Journey key record_booking is used twice.", "Journey review_booking step finish: finish is a reserved key.")
    end

    it "lets an earlier step of a signed-in journey decide whether a later one is left out" do
      flows = venue_flows.deep_dup
      flows["journeys"].first["steps"].second["skip"] = { "by" => "booking", "when" => "the booking has no guests" }
      expect(check(flows)).to eq([])

      flows["journeys"].first["steps"].second["skip"]["by"] = "guests"
      flows["journeys"].first["steps"].first["skip"] = { "by" => "booking", "when" => "always" }
      expect(check(flows)).to include("Journey record_booking step booking: the first step can't be skipped.",
                                      "Journey record_booking step guests: skip by guests is not an earlier step.")
    end

    it "keeps public sign-up steps from deciding which steps are left out" do
      flows = venue_flows.deep_dup
      flows["journeys"].first["steps"].second["skip"] = { "by" => "booking", "when" => "the booking has no guests" }
      flows["journeys"].first["audience"] = "public"

      expect(check(flows)).to include("Journey record_booking step guests: a public sign-up step can't decide which steps are skipped.")
    end
  end

  describe "steps an earlier step's processing may leave out" do
    let(:flows) do
      raw = venue_flows.deep_dup
      raw["journeys"].first["steps"].first.delete("processing")
      raw["journeys"].first["steps"].first.delete("values")
      raw["journeys"].first["steps"].second["skip"] = { "by" => "booking", "when" => "the booking has no guests" }
      described_class.new(raw)
    end
    let(:journey) { flows.journeys.first }
    let(:booking_step) { flows.steps(journey).first }

    it "names the later steps a step's submit decides on, and gives that step written processing" do
      expect(flows.skipped_by(journey, booking_step).map { |row| row["key"] }).to eq(["guests"])
      expect(flows.skipped_by(journey, flows.steps(journey).second)).to eq([])
      expect(flows.processing?(booking_step, journey)).to be(true)
      expect(flows.processing?(booking_step)).to be(false)
    end

    it "accepts the skip rule and a journey description in the schema" do
      raw = venue_flows.deep_dup
      raw["journeys"].first["description"] = "Admins record a booking and its guests."
      raw["journeys"].first["steps"].second["skip"] = { "by" => "booking", "when" => "the booking has no guests" }
      expect(described_class.schema_errors(raw)).to eq([])

      raw["journeys"].first["steps"].second["skip"] = { "by" => "Booking!", "when" => "", "extra" => 1 }
      expect(described_class.schema_errors(raw)).not_to be_empty
    end

    it "tells the processing which later steps to leave out and when" do
      needs = AiAssistant::Subsystems::ProcessingBrief.needs(flows: flows, brief: brief, entities: {})
      purpose = needs.find { |need| need["step"] == "booking" }.fetch("purpose")

      expect(purpose).to include("use skip_journey_steps with the step key",
                                 "- leave out \"Guests\" (step key guests) when the booking has no guests")
      expect(needs.find { |need| need["step"] == "guests" }).to be_nil
    end
  end

  describe AiAssistant::Subsystems::Lifecycles do
    it "lets whoever walks a journey make its status moves, and a payment move it on its own" do
      flows = venue_flows.deep_dup
      flows["objects"].second["status"]["states"] << "Paid"
      flows["journeys"] << { "key" => "pay", "name" => "Pay", "audience" => "admin", "start" => { "object" => "Booking", "status_in" => ["Approved"] },
                             "steps" => [{ "key" => "pay", "kind" => "update", "object" => "Booking", "label" => "Pay", "edits" => "start",
                                           "fields" => ["Booking date"], "status_to" => "Approved", "paid_status" => "paid" }] }

      expect(described_class.call(AiAssistant::Subsystems::Flows.new(flows))).to eq(
        "booking" => [
          { "from" => "Requested", "to" => "Approved", "by" => ["admin"] },
          { "from" => "Requested", "to" => "Declined", "by" => ["admin"] },
          { "from" => "Approved", "to" => "Paid", "by" => ["system"] }
        ]
      )
    end

    it "moves a new record from its initial state when the create step sets one" do
      flows = venue_flows.deep_dup
      flows["journeys"].first["steps"].first["status_to"] = "Approved"

      expect(described_class.call(AiAssistant::Subsystems::Flows.new(flows))["booking"]).to include({ "from" => "Requested", "to" => "Approved", "by" => ["admin"] })
    end
  end

  describe AiAssistant::Subsystems::Coverage do
    let(:customer) { create(:customer) }
    let(:flows) { AiAssistant::Subsystems::Flows.new(venue_flows) }
    let(:needs) { AiAssistant::Subsystems::EntityNeeds.call(flows: flows, brief: brief) }
    let(:mapper) { EntityDefinitions::Api::Mapper.new(customer: customer) }

    def definitions(input = venue_entities)
      input["entities"].to_h { |spec| [spec["name"].downcase, mapper.to_definition(spec)] }
    end

    def coverage(input = venue_entities) = described_class.call(needs: needs, definitions: definitions(input), customer_id: customer.id, logins: false)

    it "accepts entities that give the flows every field, reference and status move" do
      expect(coverage).to eq([])
    end

    it "names what is missing" do
      input = venue_entities.deep_dup
      booking = input["entities"].second
      booking["attributes"].delete_at(1)
      booking["attributes"].last["lifecycle"]["transitions"].pop
      input["entities"].third["attributes"].pop
      input["entities"].shift

      expect(coverage(input)).to eq([
        "Entity Venue is missing.",
        "Booking: add the field Booking date.",
        "Booking: let admin move Booking status from Requested to Declined in its lifecycle.",
        "Guest: add a reference to Booking."
      ])
    end

    it "wants the status as a select with its states and the initial state as default" do
      input = venue_entities.deep_dup
      status = input["entities"].second["attributes"].last
      status["options"]["values"] = [{ "label" => "Requested" }, { "label" => "Approved", "default" => true }, { "label" => "Declined" }]

      expect(coverage(input)).to eq(["Booking: make Requested the default option of Booking status."])

      status["options"]["values"].pop
      expect(coverage(input)).to eq(["Booking: give Booking status the options Declined."])
    end
  end

  describe AiAssistant::Subsystems::Review do
    it "approves the Build answer in any locale or a skipped card, and takes anything else as the change" do
      %i[en zh-CN].each do |locale|
        I18n.with_locale(locale) do
          body = "#{I18n.t('ai_assistant.subsystems.review.question')}\n#{I18n.t('ai_assistant.subsystems.review.approve')}"
          expect(described_class.approved?(body)).to be(true)
        end
      end
      expect(described_class.approved?(I18n.t("ai_assistant.assistant.questions.skip_reply"))).to be(true)

      typed = "#{I18n.t('ai_assistant.subsystems.review.question')}\nAdd a cancel step.\nAnd a reminder."
      expect(described_class.approved?(typed)).to be(false)
      expect(described_class.feedback(typed)).to eq("Add a cancel step.\nAnd a reminder.")
    end

    it "summarises the journeys, where they start and the statuses" do
      summary = described_class.summary(AiAssistant::Subsystems::Flows.new(venue_flows), name: "Venue Bookings")

      expect(summary).to include(
        "**Review a booking** (#{I18n.t('ai_assistant.subsystems.review.audiences.admin')})",
        I18n.t("ai_assistant.subsystems.review.starts", record: "Booking", states: "Requested"),
        "2. #{I18n.t('ai_assistant.subsystems.review.steps.add', label: 'Guests', record: 'Guest', fields: 'Guest name')}",
        "- #{I18n.t('ai_assistant.subsystems.review.status', record: 'Booking', states: 'Requested, Approved, Declined')}"
      )
    end
  end
end
