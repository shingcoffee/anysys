# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::RecordStarts do
  include JourneyPageHelpers

  let(:customer) { create(:customer) }
  include_context "student course association"

  let!(:course_page) { course_journey_page }
  let(:association_class) { Struct.new(:bridge, :source_slug) }

  def record_journey(key, first:, inputs: {}, entity: student_entity, customer: self.customer, condition: nil, **attributes)
    create(:journey, :launched, customer: customer, key: key, name: key.humanize, **attributes, definition: { "steps" => [
      { "key" => "record", "kind" => "record", "entity_id" => entity.id.to_s, "when" => condition }.compact,
      { "key" => "first", "kind" => inputs.any? ? "relate" : "create", "action_key" => first, "inputs" => inputs },
      { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "record" } }
    ] }.to_json)
  end

  def starts(entity = student_entity) = described_class.new(entity: entity, customer_id: customer.id)

  it "lists the live admin journeys that start from the record type, by name, with their first page and locked field" do
    student_journey_page
    courses = record_journey("student_courses", first: "student_add_course", inputs: { "student" => "record" })
    again = record_journey("again", first: "student_new")

    expect(starts.all.map { |start| [start.journey, start.page, start.field] })
      .to eq([[again, Page.find_by(action_key: "student_new"), nil], [courses, course_page, "student"]])
    expect(starts.find("student_courses").journey).to eq(courses)
    expect(starts.find("nope")).to be_nil
  end

  it "skips drafts, other audiences, other record types, other tenants and first pages admins don't have" do
    record_journey("draft", first: "student_add_course", inputs: { "student" => "record" }, status: :draft)
    record_journey("members", first: "student_add_course", inputs: { "student" => "record" }, visible_audiences: %w[member])
    record_journey("courses", first: "student_add_course", inputs: { "student" => "record" }, entity: course_entity)
    record_journey("missing", first: "nowhere")
    create(:journey, :launched, customer: customer)
    record_journey("elsewhere", first: "student_add_course", inputs: { "student" => "record" }, customer: create(:customer))

    expect(starts.all).to be_empty
    expect(starts(course_entity).all.map { |start| start.journey.key }).to eq(["courses"])
  end

  it "matches a start to the association section whose rows its first page adds, the rest going to the header" do
    student_journey_page
    courses = record_journey("student_courses", first: "student_add_course", inputs: { "student" => "record" })
    again = record_journey("again", first: "student_new")
    section = association_class.new(bridge_entity, "student")

    expect(starts.for_association(section).journey).to eq(courses)
    expect(starts.for_association(association_class.new(bridge_entity, "course"))).to be_nil
    expect(starts.unsectioned([section]).map(&:journey)).to eq([again])
    expect(starts.unsectioned(nil).map(&:journey)).to eq([again, courses])
  end

  describe "for one record" do
    let!(:bob) { create(:entity_entry, :with_data, customer: customer, entity: student_entity, entry_data: { "full_name" => "Bob" }) }

    def keys_for(entry) = described_class.new(entity: student_entity, customer_id: customer.id, entry: entry).all.map { |start| start.journey.key }

    it "lists only the journeys whose start condition admits the record" do
      record_journey("any", first: "student_add_course", inputs: { "student" => "record" })
      record_journey("ada_only", first: "student_add_course", inputs: { "student" => "record" },
                                 condition: { "field" => "full_name", "in" => %w[Ada Grace] })

      expect(keys_for(student)).to eq(%w[ada_only any])
      expect(keys_for(bob)).to eq(%w[any])
      expect(starts.all.map { |start| start.journey.key }).to eq(%w[ada_only any])
    end
  end

  describe "for members" do
    let!(:member_course_page) { course_journey_page(audience_admin: false, audience_member: true) }

    def member_starts = described_class.new(entity: student_entity, customer_id: customer.id, audience: EntityAttributeAudience::MEMBER)

    before do
      record_journey("members", first: "student_add_course", inputs: { "student" => "record" }, visible_audiences: %w[member])
      record_journey("admins", first: "student_add_course", inputs: { "student" => "record" })
    end

    it "lists the live member journeys, with the member's first page, from a record type a member owns" do
      allow(People::Ownership).to receive(:kind).with(student_entity).and_return(:owned)

      expect(member_starts.all.map { |start| [start.journey.key, start.page] }).to eq([["members", member_course_page]])
      expect(starts.all.map { |start| start.journey.key }).to eq(%w[admins])
    end

    it "offers none from a record type no member owns" do
      allow(People::Ownership).to receive(:kind).with(student_entity).and_return(:open)

      expect(member_starts.all).to eq([])
      expect(member_starts.find("members")).to be_nil
    end
  end

  describe ".begin!" do
    it "issues the viewer's run on the first page step, holding the record under the record step" do
      admin = create(:user, :admin, customer: customer)
      record_journey("student_courses", first: "student_add_course", inputs: { "student" => "record" })
      start = starts.find("student_courses")

      token = described_class.begin!(start: start, entry: student, viewer: admin, session: {})

      run = JourneyRun.find_by(token_digest: JourneyRun.digest_for(token))
      expect(run).to have_attributes(journey_id: start.journey.id, customer_id: customer.id, user_id: admin.id,
                                     current_step: "first", records: { "record" => [student.id.to_s] })
    end
  end
end
