# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journey do
  let(:customer) { create(:customer) }

  it "builds a valid draft from the factory and parses its steps" do
    journey = create(:journey, customer: customer)

    expect(journey).to be_draft
    expect(journey.steps_definition).to be_valid
    expect(journey.steps_definition.action_keys).to eq(%w[student_new student_add_course])
    expect(create(:journey, :launched, customer: customer)).to be_launched
  end

  it "requires a key in the action key format" do
    ["", nil, "1st", "has space", "Upper", "a", "x" * 64].each do |key|
      journey = build(:journey, customer: customer, key: key)
      expect(journey).not_to be_valid, "expected #{key.inspect} to be rejected"
      expect(journey.errors[:key]).to be_present
    end
    expect(build(:journey, customer: customer, key: "student_enrolment")).to be_valid
  end

  it "keeps keys unique within a customer only" do
    create(:journey, customer: customer, key: "enrolment")

    expect(build(:journey, customer: customer, key: "enrolment")).not_to be_valid
    expect(build(:journey, customer: create(:customer), key: "enrolment")).to be_valid
  end

  it "needs at least one audience" do
    journey = build(:journey, customer: customer)
    journey.visible_audiences = []

    expect(journey).not_to be_valid
    expect(journey.errors[:base]).to include(I18n.t("journeys.launch.errors.audiences_blank"))

    journey.visible_audiences = %w[public member bogus]
    expect(journey).to be_valid
    expect(journey.visible_audiences).to eq(%w[member public])
    expect(journey.visible_to?(:public)).to be(true)
    expect(journey.visible_to?("admin")).to be(false)
  end

  it "scopes to a customer and orders by name" do
    beta = create(:journey, customer: customer, name: "beta")
    alpha = create(:journey, customer: customer, name: "Alpha")
    create(:journey, name: "Aardvark")

    expect(described_class.for_customer(customer.id).by_name).to eq([alpha, beta])
  end

  it "finds journeys by their first step's page and by any of a list of audiences in SQL" do
    admin = create(:journey, customer: customer)
    member = create(:journey, customer: customer, visible_audiences: %w[member])
    other_start = create(:journey, customer: customer, definition: {
      "steps" => [{ "key" => "start", "kind" => "create", "action_key" => "course_new" },
                  { "key" => "finish", "kind" => "finish", "target" => { "kind" => "page", "action_key" => "student_new" } }]
    }.to_json)

    expect(described_class.starting_on("student_new")).to contain_exactly(admin, member)
    expect(described_class.starting_on("course_new")).to eq([other_start])
    expect(described_class.for_any_audience(%w[member public])).to eq([member])
    expect(described_class.for_any_audience(%w[admin member])).to contain_exactly(admin, member, other_start)
    expect(described_class.for_any_audience(%w[bogus])).to be_empty
  end

  it "deletes its runs with it" do
    journey = create(:journey, customer: customer)
    JourneyRun.issue!(customer_id: customer.id, user: nil, session: {}, journey: journey, current_step: "start")

    expect { journey.destroy! }.to change(JourneyRun, :count).by(-1)
  end
end
