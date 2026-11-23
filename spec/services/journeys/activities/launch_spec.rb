# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::Activities::Launch do
  let(:customer) { create(:customer) }
  include_context "student course association"
  let(:domain) { create(:entity_domain, customer: customer, name: "School") }

  before { [student_entity, course_entity].each { |entity| EntityDomains::Memberships.place!(entity, domain) } }

  def draft_journey
    Journeys::Activities::Generate.call(customer: customer, domain_id: domain.id, candidate_key: "create-#{student_entity.id}").journey
  end

  it "launches a journey whose checks pass" do
    result = described_class.call(journey: draft_journey)

    expect([result.ok, result.errors, result.journey.reload.launched?]).to eq([true, [], true])
  end

  it "keeps the journey a draft and returns the check errors when a step page is offline" do
    journey = draft_journey
    Page.find_by(customer_id: customer.id, action_key: "student_new").update_columns(launched: false)

    result = described_class.call(journey: journey)

    expect(result.ok).to be(false)
    expect(result.errors).not_to be_empty
    expect(journey.reload).to be_draft
  end
end
