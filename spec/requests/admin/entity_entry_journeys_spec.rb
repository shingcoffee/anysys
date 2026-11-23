# frozen_string_literal: true

require "rails_helper"

# POST /:cid/admin/entities/:entity_id/entries/:entry_id/journeys/:key
# (Admin::EntityEntryJourneysController): a journey that starts from an
# existing record begins holding that record and opens its first page with
# the record locked in. The record's page offers it from the matching
# association section's "+ Add", or from the header when no section fits.
RSpec.describe "Admin::EntityEntryJourneys", type: :request do
  include_context "as admin"
  include_context "student course association"

  let!(:course_page) { course_journey_page }
  let(:record_definition) do
    { "steps" => [
      { "key" => "record", "kind" => "record", "entity_id" => student_entity.id.to_s },
      { "key" => "courses", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "record" }, "repeat" => true },
      { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "record" } }
    ] }.to_json
  end
  let!(:journey) do
    create(:journey, :launched, customer: customer, key: "student_add_course_journey", name: "Add courses", definition: record_definition)
  end

  def start_path(entry = student, key = journey.key, entity: student_entity)
    "/#{customer.id}/admin/entities/#{entity.id}/entries/#{entry.id}/journeys/#{key}"
  end

  def entry_path = admin_entity_entry_path(customer.id, student_entity, student.id)
  def doc = Nokogiri::HTML(response.body)
  def progress = doc.at_css("[data-role='journey-progress']")
  def bridge_rows = EntityEntry.where(customer_id: customer.id, entity_id: bridge_entity.id)
  def run_for(token) = JourneyRun.find_by(token_digest: JourneyRun.digest_for(token))

  def add_course(token, course, intent: nil)
    post "/#{customer.id}/page/#{course_page.public_uuid}?#{{ return_to: PageRendering::ENTITY_ENTRY_RETURN, page: course_page.id }.to_query}",
         params: { _run: token, _intent: intent, entity: { course: course.id.to_s, status: "enrolled" } }.compact
  end

  it "starts the run holding the student and walks the courses back to the student" do
    expect { post start_path }.to change(JourneyRun, :count).by(1)

    expect(response).to have_http_status(:see_other)
    location = Addressable::URI.parse(response.location)
    expect(location.path).to eq(new_admin_entity_entry_path(customer.id, bridge_entity))
    token = location.query_values["run"]
    expect(location.query_values).to include("page" => course_page.id.to_s)
    expect(run_for(token)).to have_attributes(journey_id: journey.id, current_step: "courses", user_id: admin.id,
                                              records: { "record" => [student.id.to_s] })

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(progress.text).to include(I18n.t("journeys.runtime.step_of", current: 1, total: 1))
    expect(doc.at_css("[data-role='locked-inputs']").text).to include("Ada")
    expect(doc.at_css("select[name='entity[student]']")).to be_nil

    expect { add_course(token, math, intent: "add_another") }.to change(bridge_rows, :count).by(1)
    add_course(token, physics)

    expect(response).to redirect_to(entry_path)
    expect(run_for(token)).to be_completed
    expect(bridge_rows.map { |row| row.data_json["student"].to_s }.uniq).to eq([student.id.to_s])
  end

  it "returns to the record when the journey is unknown, offline, or starts from another record type" do
    [journey.key, "nope"].each do |key|
      journey.update!(status: :draft) if key == journey.key
      expect { post start_path(student, key) }.not_to change(JourneyRun, :count)
      expect(response).to redirect_to(entry_path)
      expect(flash[:alert]).to eq(I18n.t("journeys.runtime.unavailable"))
    end

    journey.update!(status: :launched)
    expect { post start_path(math, entity: course_entity) }.not_to change(JourneyRun, :count)
    expect(response).to redirect_to(admin_entity_entry_path(customer.id, course_entity, math.id))
  end

  it "does not start a journey for another audience" do
    journey.update!(visible_audiences: %w[member])

    expect { post start_path }.not_to change(JourneyRun, :count)
    expect(flash[:alert]).to eq(I18n.t("journeys.runtime.unavailable"))
  end

  it "404s for another tenant's record" do
    foreign = create(:entity_entry, :with_data, customer: create(:customer), entity: student_entity, entry_data: { "full_name" => "Eve" })
    post start_path(foreign)

    expect(response).to have_http_status(:not_found)
    expect(JourneyRun.count).to eq(0)
  end

  it "404s for a bridge row" do
    post start_path(enroll(student, math), entity: bridge_entity)

    expect(response).to have_http_status(:not_found)
    expect(JourneyRun.count).to eq(0)
  end

  it "refuses a member" do
    sign_in create(:user, :member, customer: customer)

    expect { post start_path }.not_to change(JourneyRun, :count)
    expect(response).not_to have_http_status(:see_other)
  end

  describe "the record's page" do
    def section = doc.css("section").find { |node| node.at_css("[data-journey-start]") }

    it "turns the course section's Add into the journey start" do
      get entry_path

      button = doc.at_css("form[action='#{start_path}'] button[data-journey-start='#{journey.key}']")
      expect(button).to be_present
      expect(button["title"]).to eq(I18n.t("journeys.runtime.start_from_record", name: "Add courses"))
      expect(doc.css("[data-journey-start]").size).to eq(1)
    end

    it "offers a journey whose first page fits no section from the header" do
      student_journey_page
      other = create(:journey, :launched, customer: customer, key: "student_redo", name: "Register again", definition: { "steps" => [
        { "key" => "record", "kind" => "record", "entity_id" => student_entity.id.to_s },
        { "key" => "again", "kind" => "create", "action_key" => "student_new" },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "record" } }
      ] }.to_json)
      get entry_path

      header = doc.at_css("form[action='#{start_path(student, other.key)}'] button[data-journey-start='#{other.key}']")
      expect(header.text).to include("Register again")
      expect(doc.at_css("form[action='#{start_path}'] button[data-journey-start='#{journey.key}']")).to be_present
    end

    it "keeps the plain Add when no live journey starts from the record" do
      journey.update!(status: :draft)
      get entry_path

      expect(doc.at_css("[data-journey-start]")).to be_nil
    end
  end
end
