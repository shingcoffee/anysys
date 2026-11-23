# frozen_string_literal: true

require "rails_helper"

# A journey walks a visitor through its steps' pages: the first page's submit
# starts the run, each step's record is kept, a repeatable step offers "Save
# and add another", and the finish opens the record (or page) it names.
RSpec.describe "Journey runtime", type: :request do
  include_context "as admin"
  include_context "student course association"

  let!(:student_page) { student_journey_page }
  let!(:course_page) { course_journey_page }
  let!(:journey) { create(:journey, :launched, customer: customer) }

  def doc = Nokogiri::HTML(response.body)
  def progress = doc.at_css("[data-role='journey-progress']")
  def bridge_rows = EntityEntry.where(customer_id: customer.id, entity_id: bridge_entity.id)
  def run_for(token) = JourneyRun.find_by(token_digest: JourneyRun.digest_for(token))

  def submit_path(page, **query)
    "/#{customer.id}/page/#{page.public_uuid}?#{{ return_to: PageRendering::ENTITY_ENTRY_RETURN }.merge(query).to_query}"
  end

  def start_journey
    post submit_path(student_page), params: { entity: { full_name: "Grace" } }
    Addressable::URI.parse(response.location).query_values["run"]
  end

  def add_course(token, course, intent: nil)
    post submit_path(course_page, page: course_page.id),
         params: { _run: token, _intent: intent, entity: { course: course.id.to_s, status: "enrolled" } }.compact
  end

  it "walks an admin from the new student to the student's courses and back to the student" do
    get new_admin_entity_entry_path(customer.id, student_entity)
    expect(progress.text).to include(I18n.t("journeys.runtime.step_of", current: 1, total: 2))
    expect(doc.at_css("button[name='_intent']")).to be_nil

    token = start_journey
    grace = EntityEntry.where(entity_id: student_entity.id).order(:id).last
    location = Addressable::URI.parse(response.location)
    expect(location.path).to eq(new_admin_entity_entry_path(customer.id, bridge_entity))
    expect(location.query_values).to include("page" => course_page.id.to_s, "run" => be_present)
    expect(run_for(token)).to have_attributes(journey_id: journey.id, current_step: "relate_1", user_id: admin.id,
                                              records: { "start" => [grace.id.to_s] })

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(progress.text).to include(I18n.t("journeys.runtime.step_of", current: 2, total: 2), "Add Course for Student")
    expect(doc.at_css("[data-role='locked-inputs']").text).to include("Grace")
    expect(doc.at_css("select[name='entity[student]']")).to be_nil
    expect(doc.at_css("button[type='submit'][name='_intent'][value='add_another']").text)
      .to include(I18n.t("journeys.runtime.save_and_add_another"))

    [math, physics].each do |course|
      expect { add_course(token, course, intent: "add_another") }.to change(bridge_rows, :count).by(1)
      location = Addressable::URI.parse(response.location)
      expect(location.path).to eq(new_admin_entity_entry_path(customer.id, bridge_entity))
      expect(location.query_values).to include("page" => course_page.id.to_s, "run" => token)
      expect(flash[:notice]).to eq(I18n.t("journeys.runtime.saved_add_another"))
      expect(bridge_rows.order(:id).last.data_json["student"].to_s).to eq(grace.id.to_s)
    end

    history = create(:entity_entry, :with_data, customer: customer, entity: course_entity, entry_data: { "code" => "HIST-110" })
    add_course(token, history)

    expect(response).to redirect_to(admin_entity_entry_path(customer.id, student_entity, grace.id))
    expect(flash[:notice]).to eq(I18n.t("journeys.runtime.completed"))
    expect(run_for(token)).to be_completed
    expect(run_for(token).records["relate_1"].size).to eq(3)
    expect(bridge_rows.where("data LIKE ?", "%#{grace.id}%").count).to eq(3)
  end

  it "finishes on the page the journey names" do
    definition = journey.steps_definition.to_h
    definition["steps"].last["target"] = { "kind" => "page", "action_key" => "student_new" }
    journey.update!(definition: definition.to_json)
    token = start_journey

    add_course(token, math)

    location = Addressable::URI.parse(response.location)
    expect(location.path).to eq(new_admin_entity_entry_path(customer.id, student_entity))
    expect(location.query_values).to eq("page" => student_page.id.to_s)
    expect(run_for(token)).to be_completed
  end

  it "keeps the run on the step when a submit is refused" do
    token = start_journey

    post submit_path(course_page, page: course_page.id), params: { _run: token, entity: { course: "", status: "enrolled" } }

    location = Addressable::URI.parse(response.location)
    expect(location.query_values).to include("page" => course_page.id.to_s, "run" => token)
    expect(run_for(token)).to have_attributes(current_step: "relate_1", status: "active")
  end

  it "ignores the run on a page that isn't the current step" do
    _run, token = JourneyRun.issue!(customer_id: customer.id, user: admin, session: {}, journey: journey, current_step: "start")

    get new_admin_entity_entry_path(customer.id, bridge_entity, page: course_page.id, run: token)

    expect(response).to have_http_status(:ok)
    expect(progress).to be_nil
    expect(doc.at_css("[data-role='locked-inputs']")).to be_nil
    expect(doc.at_css("select[name='entity[student]']")).to be_present

    post submit_path(course_page, page: course_page.id),
         params: { _run: token, entity: { student: student.id.to_s, course: math.id.to_s, status: "enrolled" } }
    expect(run_for(token)).to have_attributes(current_step: "start", records: {})
  end

  it "doesn't start a draft journey" do
    journey.draft!

    get new_admin_entity_entry_path(customer.id, student_entity)
    expect(progress).to be_nil

    post submit_path(student_page), params: { entity: { full_name: "Grace" } }
    expect(response.location).not_to include("run=")
    expect(JourneyRun.count).to eq(0)
  end

  it "doesn't start when editing an existing record" do
    get edit_admin_entity_entry_path(customer.id, student_entity, student)
    expect(progress).to be_nil

    post submit_path(student_page, entry_id: student.id), params: { entity: { full_name: "Ada Lovelace" } }
    expect(student.reload.data_json["full_name"]).to eq("Ada Lovelace")
    expect(JourneyRun.count).to eq(0)
  end

  it "doesn't start from a quick-add dialog" do
    get new_admin_entity_entry_path(customer.id, student_entity),
        headers: { "Turbo-Frame" => Admin::Entities::QuickAddDialogComponent.frame_id(0) }
    expect(progress).to be_nil

    post submit_path(student_page), params: { entity: { full_name: "Grace" } },
                                    headers: { "Turbo-Frame" => Admin::Entities::QuickAddDialogComponent.frame_id(0) }
    expect(JourneyRun.count).to eq(0)
  end

  describe "previewing a draft" do
    before { journey.draft! }

    it "lets the platform owner start it through ?journey=" do
      sign_in find_or_create_platform_owner

      get new_admin_entity_entry_path(customer.id, student_entity, journey: journey.key)
      expect(progress.text).to include(I18n.t("journeys.runtime.step_of", current: 1, total: 2))
      expect(doc.at_css("input[type='hidden'][name='_journey']")["value"]).to eq(journey.key)

      post submit_path(student_page), params: { _journey: journey.key, entity: { full_name: "Grace" } }
      token = Addressable::URI.parse(response.location).query_values["run"]
      expect(run_for(token)).to have_attributes(journey_id: journey.id, current_step: "relate_1")
    end

    it "is ignored for a tenant admin" do
      get new_admin_entity_entry_path(customer.id, student_entity, journey: journey.key)
      expect(progress).to be_nil
      expect(doc.at_css("input[name='_journey']")).to be_nil

      post submit_path(student_page), params: { _journey: journey.key, entity: { full_name: "Grace" } }
      expect(JourneyRun.count).to eq(0)
    end
  end

  describe "finishing on a record as an anonymous visitor" do
    before { sign_out admin }

    let!(:student_page) { student_journey_page(audience_admin: false, audience_public: true) }
    let!(:course_page) { course_journey_page(audience_admin: false, audience_public: true) }
    let!(:journey) { create(:journey, :launched, customer: customer, audience_admin: false, audience_public: true) }

    it "carries the run through the public pages and lands back on the last page" do
      get "/#{customer.id}/page/#{student_page.public_uuid}"
      expect(progress.text).to include(I18n.t("journeys.runtime.step_of", current: 1, total: 2))

      post "/#{customer.id}/page/#{student_page.public_uuid}", params: { entity: { full_name: "Grace" } }
      location = Addressable::URI.parse(response.location)
      expect(location.path).to eq("/#{customer.id}/page/#{course_page.public_uuid}")
      token = location.query_values["run"]

      follow_redirect!
      expect(doc.at_css("[data-role='locked-inputs']").text).to include("Grace")

      post "/#{customer.id}/page/#{course_page.public_uuid}",
           params: { _run: token, entity: { course: math.id.to_s, status: "enrolled" } }
      expect(response.location).to end_with("/#{customer.id}/page/#{course_page.public_uuid}")
      expect(flash[:notice]).to eq(I18n.t("journeys.runtime.completed"))
      expect(run_for(token)).to be_completed
    end
  end

  describe "finishing on a record as a member" do
    let(:member) { create(:user, :member, customer: customer) }
    let!(:student_page) { student_journey_page(audience_admin: false, audience_member: true) }
    let!(:course_page) { course_journey_page(audience_admin: false, audience_member: true) }
    let!(:journey) { create(:journey, :launched, customer: customer, audience_admin: false, audience_member: true) }

    before do
      sign_out admin
      sign_in member
    end

    it "opens the new record on the member's own surface" do
      post "/#{customer.id}/page/#{student_page.public_uuid}", params: { entity: { full_name: "Grace" } }
      token = Addressable::URI.parse(response.location).query_values["run"]
      grace = EntityEntry.where(entity_id: student_entity.id).order(:id).last
      expect(run_for(token)).to have_attributes(user_id: member.id, current_step: "relate_1")

      post "/#{customer.id}/page/#{course_page.public_uuid}",
           params: { _run: token, entity: { course: math.id.to_s, status: "enrolled" } }

      expect(response).to redirect_to(member_surface_path(customer.id, "entity_#{student_entity.id}", grace.id))
      expect(flash[:notice]).to eq(I18n.t("journeys.runtime.completed"))
      expect(run_for(token)).to be_completed
    end
  end

  describe "skipping" do
    def skip_step(page, token)
      post submit_path(page, page: page.id), params: { _run: token, _intent: "skip" }
    end

    def set_steps(*working, finish: { "kind" => "record", "step" => "start" })
      journey.update!(definition: { "steps" => working + [{ "key" => "finish", "kind" => "finish", "target" => finish }] }.to_json)
    end

    def optional_relate(**extra)
      { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course",
        "inputs" => { "student" => "start" }, "repeat" => true, "optional" => true }.merge(extra)
    end

    it "shows Skip on an optional step and not on a required one" do
      token = start_journey
      follow_redirect!
      expect(doc.at_css("button[type='submit'][name='_intent'][value='skip']")).to be_nil
      expect(doc.at_css("button[type='submit'][name='_intent'][value='add_another']")).to be_present

      set_steps(
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        optional_relate
      )
      get new_admin_entity_entry_path(customer.id, bridge_entity, page: course_page.id, run: token)

      button = doc.at_css("button[type='submit'][name='_intent'][value='skip'][formnovalidate]")
      expect(button).to be_present
      expect(button.text).to include(I18n.t("journeys.runtime.skip"))
      expect(progress.text).to include(I18n.t("journeys.optional"))
    end

    it "skips an optional step without saving and moves to the next reachable page" do
      note_page = journey_page(student_entity, action_key: "student_note", fields: [journey_text_field("full_name")],
                                              form_settings: { modes: ["create"] }, name: "Optional note")
      set_steps(
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "note", "kind" => "create", "action_key" => "student_note", "optional" => true },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" } }
      )
      token = start_journey
      expect(run_for(token).current_step).to eq("note")

      expect { skip_step(note_page, token) }.not_to change(EntityEntry, :count)
      location = Addressable::URI.parse(response.location)
      expect(location.path).to eq(new_admin_entity_entry_path(customer.id, bridge_entity))
      expect(location.query_values).to include("page" => course_page.id.to_s, "run" => token)
      expect(flash[:notice]).to eq(I18n.t("journeys.runtime.skipped"))
      expect(run_for(token)).to have_attributes(current_step: "relate_1")
      expect(run_for(token).records.keys).to eq(["start"])
    end

    it "passes a step the first page's processing leaves out, only when the journey lets processing skip it" do
      journey_page(student_entity, action_key: "student_note", fields: [journey_text_field("full_name")],
                                   form_settings: { modes: ["create"] }, name: "Optional note")
      bind_page_flowchart(student_page, steps: [{ "action" => "skip_journey_steps", "config" => { "steps" => %w[note] } }])
      note = { "key" => "note", "kind" => "create", "action_key" => "student_note" }
      relate = { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" } }

      set_steps({ "key" => "start", "kind" => "create", "action_key" => "student_new" }, note.merge("conditional" => true), relate)
      token = start_journey
      location = Addressable::URI.parse(response.location)
      expect(location.query_values).to include("page" => course_page.id.to_s, "run" => token)
      expect(run_for(token)).to have_attributes(current_step: "relate_1", skipped: %w[note])

      set_steps({ "key" => "start", "kind" => "create", "action_key" => "student_new" }, note, relate)
      expect(run_for(start_journey)).to have_attributes(current_step: "note", skipped: [])
    end

    it "refuses to skip a required step" do
      token = start_journey
      entries = EntityEntry.count

      skip_step(course_page, token)

      location = Addressable::URI.parse(response.location)
      expect(location.query_values).to include("page" => course_page.id.to_s, "run" => token)
      expect(flash[:alert]).to eq(I18n.t("journeys.runtime.skip_unavailable"))
      expect(run_for(token)).to have_attributes(current_step: "relate_1", status: "active")
      expect(EntityEntry.count).to eq(entries)
    end

    it "passes dependents of a skipped step and lands on an independent one" do
      course_create = course_create_journey_page
      enrolment_journey_page
      set_steps(
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "course", "kind" => "create", "action_key" => "course_new", "optional" => true },
        { "key" => "enrol", "kind" => "relate", "action_key" => "enrolment_new",
          "inputs" => { "student" => "start", "course" => "course" } },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course",
          "inputs" => { "student" => "start" }, "repeat" => true }
      )
      token = start_journey
      skip_step(course_create, token)

      location = Addressable::URI.parse(response.location)
      expect(location.path).to eq(new_admin_entity_entry_path(customer.id, bridge_entity))
      expect(location.query_values).to include("page" => course_page.id.to_s, "run" => token)
      expect(flash[:notice]).to eq(I18n.t("journeys.runtime.skipped"))
      expect(run_for(token)).to have_attributes(current_step: "relate_1")
      expect(run_for(token).records.keys).to eq(["start"])

      get new_admin_entity_entry_path(customer.id, bridge_entity, page: course_page.id, run: token)
      expect(progress.text).to include(I18n.t("journeys.runtime.step_of", current: 4, total: 4))
    end

    it "finishes with the custom message when the last page step is skipped" do
      set_steps(
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        optional_relate,
        finish: { "kind" => "record", "step" => "start", "message" => "Thanks for enrolling." }
      )
      token = start_journey
      grace = EntityEntry.where(entity_id: student_entity.id).order(:id).last

      expect { skip_step(course_page, token) }.not_to change(bridge_rows, :count)
      expect(response).to redirect_to(admin_entity_entry_path(customer.id, student_entity, grace.id))
      expect(flash[:notice]).to eq("Thanks for enrolling.")
      expect(run_for(token)).to be_completed
      expect(run_for(token).records.keys).to eq(["start"])
    end

    it "uses the custom finish message after a normal last submit, and the default without one" do
      token = start_journey
      add_course(token, math)
      expect(flash[:notice]).to eq(I18n.t("journeys.runtime.completed"))

      set_steps(
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course",
          "inputs" => { "student" => "start" }, "repeat" => true },
        finish: { "kind" => "record", "step" => "start", "message" => "Thanks for enrolling." }
      )
      token = start_journey
      add_course(token, math)
      expect(flash[:notice]).to eq("Thanks for enrolling.")
    end

    it "does not skip another user's run" do
      set_steps(
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        optional_relate
      )
      token = start_journey
      sign_in create(:user, :admin, customer: customer)

      skip_step(course_page, token)

      expect(flash[:alert]).to eq(I18n.t("journeys.runtime.skip_unavailable"))
      expect(run_for(token)).to have_attributes(current_step: "relate_1", status: "active")
      expect(run_for(token).records.keys).to eq(["start"])
    end
  end

  it "tells the page submit which journey and step each submit belongs to" do
    seen = []
    allow(Pages::Submit).to receive(:call).and_wrap_original do |original, **kwargs|
      seen << kwargs[:journey]
      original.call(**kwargs)
    end

    token = start_journey
    add_course(token, math)
    post submit_path(course_page), params: { entity: { student: "1", course: math.id.to_s, status: "x" } }

    expect(seen).to eq([{ "key" => journey.key, "step" => "start", "finishing" => false },
                        { "key" => journey.key, "step" => "relate_1", "finishing" => true }, nil])
  end
end
