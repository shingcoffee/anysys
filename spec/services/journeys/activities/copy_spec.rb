# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::Activities::Copy do
  let(:customer) { create(:customer) }
  let(:domain) { create(:entity_domain, customer: customer) }
  let(:journey) do
    create(:journey, customer: customer, entity_domain: domain, name: "Enrolment", key: "enrolment",
                     description: "Walk through", visible_audiences: %w[admin member])
  end

  def copy(source = journey) = described_class.call(journey: source)

  it "copies attributes onto a new draft" do
    result = copy

    expect(result.ok).to be(true)
    expect(result.errors).to eq([])
    duplicate = result.journey
    expect(duplicate).not_to eq(journey)
    expect(duplicate).to be_persisted
    expect(duplicate).to be_draft
    expect(duplicate).to have_attributes(
      customer_id: customer.id, entity_domain_id: domain.id, description: "Walk through",
      name: I18n.t("journeys.admin.copy_name", name: "Enrolment"), key: "enrolment_copy",
      visible_audiences: %w[admin member]
    )
    expect(duplicate.steps_definition.to_h).to eq(journey.steps_definition.to_h)
    expect(journey.reload).to have_attributes(name: "Enrolment", key: "enrolment")
  end

  it "suffixes the key when the copy slug is taken" do
    create(:journey, customer: customer, key: "enrolment_copy")
    create(:journey, customer: customer, key: "enrolment_copy_2")

    expect(copy.journey.key).to eq("enrolment_copy_3")
  end

  it "lets another tenant keep the same copy key" do
    create(:journey, key: "enrolment_copy")

    expect(copy.journey.key).to eq("enrolment_copy")
  end

  it "truncates a long key so the copy still matches the action-key format" do
    source = create(:journey, customer: customer, key: "k" * 63)
    first = copy(source).journey

    expect(first.key).to eq("#{'k' * 58}_copy")
    expect(first.key.length).to eq(63)
    expect(first.key).to match(PageVisibility::ACTION_KEY)

    second = copy(source).journey
    expect(second.key).to eq("#{'k' * 56}_copy_2")
    expect(second.key.length).to eq(63)
    expect(second.key).to match(PageVisibility::ACTION_KEY)
  end

  it "copies a launched journey as a draft" do
    source = create(:journey, :launched, customer: customer, key: "live", name: "Live")
    duplicate = copy(source).journey

    expect(duplicate).to be_draft
    expect(duplicate.name).to eq(I18n.t("journeys.admin.copy_name", name: "Live"))
    expect(source.reload).to be_launched
  end

  it "truncates a long copy name" do
    source = create(:journey, customer: customer, name: "N" * 120)
    name = copy(source).journey.name

    expect(name).to eq(I18n.t("journeys.admin.copy_name", name: "N" * 120).first(120))
    expect(name.length).to eq(120)
  end
end
