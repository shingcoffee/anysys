# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::Handoffs do
  let(:customer) { create(:customer) }
  include_context "booking journeys"

  subject(:handoffs) { described_class.new(customer: customer) }

  def state(value) = Journeys::StepEffects::State.new(entity_id: booking.id.to_s, field: "status", value: value)

  it "finds the journeys that pick up a record left in a state, leaving out the one asking" do
    found = handoffs.next_for([state("requested"), state("paid")])

    expect(found.map { |row| [row.journey, row.field, row.values] }).to eq([[review_journey, "status", ["requested"]]])
    expect(handoffs.next_for([state("requested")], except: review_journey)).to eq([])
  end

  it "lists the steps of other journeys that leave records in a state" do
    sources = handoffs.sources_for(booking.id, "status", "approved")

    expect(sources.map { |source| [source.journey, source.step.key, source.step_name] }).to eq([[review_journey, "review", "Review form"]])
    expect(handoffs.sources_for(booking.id, "status", "approved", except: review_journey)).to eq([])
    expect(handoffs.sources_for(booking.id, "status", "requested").map { |source| source.step_name }).to eq(["Booking details"])
  end

  it "links each journey to the ones that pick up what its steps leave behind" do
    links = handoffs.links.map { |link| [link.from, link.to, link.values] }

    expect(links).to contain_exactly([request_journey, review_journey, ["requested"]], [review_journey, pay_journey, ["approved"]])
  end

  it "resolves every journey's step pages in one lookup per audience" do
    allow(Pages::ActionResolver).to receive(:pages_for).and_call_original
    handoffs.links
    handoffs.sources_for(booking.id, "status", "paid")

    expect(Pages::ActionResolver).to have_received(:pages_for).once
  end

  it "ignores another customer's journeys" do
    other = create(:customer)
    create(:journey, customer: other, key: "review_booking", definition: review_journey.definition)

    expect(handoffs.journeys).to contain_exactly(request_journey, review_journey, pay_journey)
  end

  it "skips steps whose page no audience of the journey has" do
    review_journey.update!(visible_audiences: %w[member])

    expect(handoffs.sources_for(booking.id, "status", "approved")).to eq([])
  end
end
