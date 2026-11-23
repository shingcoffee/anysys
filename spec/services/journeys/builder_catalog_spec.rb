# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::BuilderCatalog do
  include JourneyPageHelpers

  let(:customer) { create(:customer) }
  include_context "student course association"

  let(:catalog) { described_class.new(pages: [student_journey_page, course_journey_page], domain: nil, customer_id: customer.id) }

  it "tells which pages edit records" do
    fits = catalog.pages.to_h { |page| [page.action_key, [catalog.fit(page).creates, catalog.fit(page).updates]] }

    expect(fits).to eq("student_new" => [true, true], "student_add_course" => [true, false])
  end

  describe "what each page's processing hands on" do
    include_context "booking journeys"

    def booking_catalog(journey: nil)
      described_class.new(pages: [request_page, review_page, pay_page], domain: booking_domain, customer_id: customer.id, journey: journey)
    end

    def next_line(journey, state)
      I18n.t("journeys.admin.handoffs.next", journey: journey.name, audiences: I18n.t("journeys.audiences.admin"), entity: "Booking", states: state)
    end

    def source(journey, step) = I18n.t("journeys.admin.handoffs.source", journey: journey.name, step: step)

    it "names the journeys that pick up each page's records, apart when only a new record starts in the state" do
      catalog = booking_catalog(journey: request_journey)

      expect(catalog.effects(request_page)).to have_attributes(next: [], next_creating: [next_line(review_journey, "Requested")])
      expect(catalog.effects(review_page)).to have_attributes(next: [next_line(pay_journey, "Approved")], next_creating: [])
      expect(catalog.effects(pay_page).next).to eq([])
      expect(catalog.effects(pay_page).lines).to include(I18n.t("journeys.admin.effects.paid_move", field: "Status", state: "Paid"))
    end

    it "leaves the journey being edited out of its own hand-offs" do
      expect(booking_catalog(journey: review_journey).effects(request_page).next_creating).to eq([])
    end

    it "lists, for each start-condition value, the steps of other journeys that leave records in it" do
      sources = booking_catalog(journey: pay_journey).choices.fetch(booking.id.to_s).first.options.to_h { |option| [option.value, option.sources] }

      expect(sources).to eq("requested" => source(request_journey, "Booking details"), "approved" => source(review_journey, "Review form"),
                            "declined" => source(review_journey, "Review form"), "paid" => "")
    end
  end

  describe "#choices" do
    let(:schema) do
      [
        { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
        { "name" => "Stage", "name_slug" => "stage", "html_type" => "select",
          "config" => { "options" => [{ "label" => "Applied", "value" => "applied" }, { "label" => "", "value" => "admitted" },
                                      { "label" => "Again", "value" => "applied" }, { "label" => "Blank", "value" => " " },
                                      { "label" => "Odd", "value" => { "x" => 1 } }, 3, "waitlisted"] } },
        { "name" => "Tags", "display_label" => "Labels", "name_slug" => "tags", "html_type" => "multi-select",
          "config" => { "options" => [{ "label" => "VIP", "value" => "vip" }] } },
        { "name" => "Advisor", "name_slug" => "advisor", "html_type" => "select", "type" => "EntityReference",
          "entity_id" => course_entity.id.to_s },
        { "name" => "Empty", "name_slug" => "empty", "html_type" => "radio", "config" => { "options" => [] } },
        { "name" => "Bad", "name_slug" => "Bad Slug", "html_type" => "select", "config" => { "options" => ["x"] } }
      ]
    end

    it "is keyed by record type, leaving out link entities" do
      expect(catalog.choices.keys).to contain_exactly(student_entity.id.to_s, course_entity.id.to_s)
      expect(catalog.choices.fetch(course_entity.id.to_s)).to eq([])
    end

    it "lists choice fields with fixed options by stored value, skipping references, malformed slugs and unusable values" do
      allow(catalog).to receive(:record_types).and_return([instance_double(Entity, id: 91, property_schema_json: schema + ["stray"])])
      stage, tags = catalog.choices.fetch("91")

      expect(catalog.choices.fetch("91").size).to eq(2)
      expect([stage.field, stage.label]).to eq(%w[stage Stage])
      expect(stage.options.map { |option| [option.value, option.label] })
        .to eq([%w[applied Applied], %w[admitted admitted], %w[3 3], %w[waitlisted waitlisted]])
      expect([tags.field, tags.label, tags.options.map(&:value)]).to eq(["tags", "Labels", ["vip"]])
    end
  end
end
