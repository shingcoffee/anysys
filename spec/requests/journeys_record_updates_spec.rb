# frozen_string_literal: true

require "rails_helper"

# Status-linked journeys: staff review an application while it is Submitted,
# and its member follows up on their own application once it is Approved.
# Each journey starts from the record (its `when` condition picks which
# records offer it) and its update step's page edits that very record.
RSpec.describe "Journeys that edit the record they start from", type: :request do
  include_context "as admin"

  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:member) { create(:user, :member, customer: customer) }
  let(:other_member) { create(:user, :member, customer: customer) }
  let(:applicant_entity) do
    create(:entity, customer: customer, name: "Applicant", display_label: "Applicant", extended_model: person_model,
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
  end
  let(:application_entity) do
    statuses = %w[Draft Submitted Approved].map { |value| { "label" => value, "value" => value } }
    create(:entity, customer: customer, name: "Application", display_label: "Application", property_schema: [
      { "name" => "Applicant", "name_slug" => "applicant", "html_type" => "select", "type" => "EntityReference",
        "entity_id" => applicant_entity.id.to_s },
      { "name" => "Title", "name_slug" => "title", "html_type" => "text" },
      { "name" => "Status", "name_slug" => "status", "html_type" => "select",
        "config" => { "source" => "manual", "options" => statuses } },
      { "name" => "Note", "name_slug" => "note", "html_type" => "text" }
    ].to_json)
  end

  before { enable_module!("authentication", customer).set_extendable_model!(person_model, true) }

  let!(:own_applicant) { create(:entity_entry, entity: applicant_entity, customer: customer, user: member) }
  let!(:peer_applicant) { create(:entity_entry, entity: applicant_entity, customer: customer, user: other_member) }
  let!(:review_page) do
    journey_page(application_entity, action_key: "application_review", name: "Review application",
                                      fields: [journey_text_field("status"), journey_text_field("note")],
                                      form_settings: { modes: ["update"] })
  end
  let!(:follow_up_page) do
    journey_page(application_entity, action_key: "application_follow_up", name: "Follow up",
                                      fields: [journey_text_field("note")], form_settings: { modes: ["update"] },
                                      audience_admin: false, audience_member: true)
  end
  let!(:review) { record_journey("review", "Review application", "Submitted", "application_review") }
  let!(:follow_up) do
    record_journey("follow_up", "Follow up", "Approved", "application_follow_up", audience_admin: false, audience_member: true)
  end

  def record_journey(key, name, status, action_key, **audiences)
    create(:journey, :launched, customer: customer, key: key, name: name, **audiences, definition: { "steps" => [
      { "key" => "record", "kind" => "record", "entity_id" => application_entity.id.to_s,
        "when" => { "field" => "status", "in" => [status] } },
      { "key" => key, "kind" => "update", "action_key" => action_key, "record" => "record" },
      { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "record" } }
    ] }.to_json)
  end

  def application(applicant, status, entry_customer: customer, entity: application_entity)
    create(:entity_entry, :with_data, customer: entry_customer, entity: entity,
                                      entry_data: { "applicant" => applicant.id.to_s, "title" => "Grant", "status" => status })
  end

  def doc = Nokogiri::HTML(response.body)
  def progress = doc.at_css("[data-role='journey-progress']")
  def run_for(token) = JourneyRun.find_by(token_digest: JourneyRun.digest_for(token))
  def token_of(location) = Addressable::URI.parse(location).query_values["run"]
  def submit_path(page, **query) = "/#{customer.id}/page/#{page.public_uuid}?#{query.to_query}"
  def admin_start_path(entry) = "/#{customer.id}/admin/entities/#{application_entity.id}/entries/#{entry.id}/journeys/review"
  def member_start_path(entry, key = "follow_up", entity_id: application_entity.id)
    "/#{customer.id}/member/entities/#{entity_id}/entries/#{entry.id}/journeys/#{key}"
  end
  def member_record_path(entry) = member_surface_path(customer.id, "entity_#{application_entity.id}", entry.id)

  it "passes the launch checks for both journeys" do
    expect(Journeys::LaunchChecks.new(review).errors).to eq([])
    expect(Journeys::LaunchChecks.new(follow_up).errors).to eq([])
  end

  describe "an admin reviewing a submitted application" do
    let!(:submitted) { application(own_applicant, "Submitted") }
    let!(:draft) { application(own_applicant, "Draft") }

    it "offers the review on a Submitted application and not on a Draft one" do
      get admin_entity_entry_path(customer.id, application_entity, submitted)
      expect(doc.at_css("form[action='#{admin_start_path(submitted)}'] button[data-journey-start='review']")).to be_present

      get admin_entity_entry_path(customer.id, application_entity, draft)
      expect(doc.at_css("[data-journey-start]")).to be_nil

      expect { post admin_start_path(draft) }.not_to change(JourneyRun, :count)
      expect(response).to redirect_to(admin_entity_entry_path(customer.id, application_entity, draft.id))
      expect(flash[:alert]).to eq(I18n.t("journeys.runtime.unavailable"))
    end

    it "opens the review page on that application and saves the decision onto it" do
      expect { post admin_start_path(submitted) }.to change(JourneyRun, :count).by(1)

      expect(response).to have_http_status(:see_other)
      location = Addressable::URI.parse(response.location)
      expect(location.path).to eq(edit_admin_entity_entry_path(customer.id, application_entity, submitted))
      expect(location.query_values).to include("page" => review_page.id.to_s)
      token = location.query_values["run"]
      expect(run_for(token)).to have_attributes(journey_id: review.id, current_step: "review", user_id: admin.id,
                                                records: { "record" => [submitted.id.to_s] })

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(progress.text).to include(I18n.t("journeys.runtime.step_of", current: 1, total: 1))
      expect(doc.at_css("form[action*='entry_id=#{submitted.id}']")).to be_present

      expect do
        post submit_path(review_page, return_to: PageRendering::ENTITY_ENTRY_RETURN, entry_id: submitted.id, page: review_page.id),
             params: { _run: token, entity: { status: "Approved", note: "Looks good" } }
      end.not_to change(EntityEntry, :count)

      expect(submitted.reload.data_json).to include("status" => "Approved", "note" => "Looks good", "title" => "Grant")
      expect(response).to redirect_to(admin_entity_entry_path(customer.id, application_entity, submitted.id))
      expect(flash[:notice]).to eq(I18n.t("journeys.runtime.completed"))
      expect(run_for(token)).to be_completed
      expect(run_for(token).records).to eq("record" => [submitted.id.to_s], "review" => [submitted.id.to_s])
    end
  end

  describe "a member following up on their approved application" do
    let!(:approved) { application(own_applicant, "Approved") }
    let!(:second) { application(own_applicant, "Approved") }
    let!(:peer_approved) { application(peer_applicant, "Approved") }
    let!(:submitted) { application(own_applicant, "Submitted") }

    before do
      sign_out admin
      sign_in member
    end

    def start_follow_up(entry = approved)
      post member_start_path(entry)
      token_of(response.location)
    end

    it "offers the follow-up on the member's own Approved application, not on a Submitted one" do
      get member_record_path(approved)
      expect(response).to have_http_status(:ok)
      section = doc.at_css("[data-role='record-journeys']")
      button = section.at_css("form[action='#{member_start_path(approved)}'] button[data-journey-start='follow_up']")
      expect(button.text).to include(I18n.t("journeys.runtime.start_from_record", name: "Follow up"))

      get member_record_path(submitted)
      expect(doc.at_css("[data-role='record-journeys']")).to be_nil

      expect { post member_start_path(submitted) }.not_to change(JourneyRun, :count)
      expect(response).to redirect_to(member_record_path(submitted))
      expect(flash[:alert]).to eq(I18n.t("journeys.runtime.unavailable"))
    end

    it "opens the follow-up page on the application and saves onto it" do
      expect { post member_start_path(approved) }.to change(JourneyRun, :count).by(1)

      expect(response).to have_http_status(:see_other)
      location = Addressable::URI.parse(response.location)
      expect(location.path).to eq(member_page_path(customer.id, follow_up_page))
      expect(location.query_values).to include("entry" => approved.id.to_s)
      token = location.query_values["run"]
      expect(run_for(token)).to have_attributes(journey_id: follow_up.id, current_step: "follow_up", user_id: member.id,
                                                records: { "record" => [approved.id.to_s] })

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(doc.at_css("form[action*='entry_id=#{approved.id}']")).to be_present

      expect do
        post submit_path(follow_up_page, entry_id: approved.id), params: { _run: token, entity: { note: "Thanks" } }
      end.not_to change(EntityEntry, :count)

      expect(approved.reload.data_json).to include("note" => "Thanks", "status" => "Approved")
      expect(response).to redirect_to(member_record_path(approved))
      expect(flash[:notice]).to eq(I18n.t("journeys.runtime.completed"))
      expect(run_for(token)).to be_completed
    end

    it "refuses another member's application, at the start and on the page" do
      token = start_follow_up
      expect { post member_start_path(peer_approved) }.not_to change(JourneyRun, :count)
      expect(response).to have_http_status(:not_found)

      get member_page_path(customer.id, follow_up_page, entry: peer_approved.id, run: token)
      expect(response).to have_http_status(:not_found)

      post submit_path(follow_up_page, entry_id: peer_approved.id), params: { _run: token, entity: { note: "Mine now" } }
      expect(peer_approved.reload.data_json).not_to have_key("note")
      expect(run_for(token)).to have_attributes(current_step: "follow_up", status: "active")
    end

    it "refuses the member's own application that the run does not hold, and any edit without the run" do
      token = start_follow_up

      get member_page_path(customer.id, follow_up_page, entry: second.id, run: token)
      expect(response).to have_http_status(:not_found)
      post submit_path(follow_up_page, entry_id: second.id), params: { _run: token, entity: { note: "Swapped" } }
      expect(second.reload.data_json).not_to have_key("note")

      get member_page_path(customer.id, follow_up_page, entry: approved.id)
      expect(response).to have_http_status(:not_found)
      post submit_path(follow_up_page, entry_id: approved.id), params: { entity: { note: "No run" } }
      expect(approved.reload.data_json).not_to have_key("note")
      expect(run_for(token)).to have_attributes(current_step: "follow_up", status: "active")
    end

    it "refuses another tenant's application" do
      other_customer = create(:customer)
      foreign = application(own_applicant, "Approved", entry_customer: other_customer)
      token = start_follow_up

      expect { post member_start_path(foreign) }.not_to change(JourneyRun, :count)
      expect(response).to have_http_status(:not_found)

      post submit_path(follow_up_page, entry_id: foreign.id), params: { _run: token, entity: { note: "Elsewhere" } }
      expect(foreign.reload.data_json).not_to have_key("note")

      foreign_entity = create(:entity, customer: other_customer, name: "Application")
      expect { post member_start_path(foreign, entity_id: foreign_entity.id) }.not_to change(JourneyRun, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "is closed to admins, who start record journeys from the admin record page" do
      sign_in admin

      expect { post member_start_path(approved) }.not_to change(JourneyRun, :count)
      expect(response).not_to have_http_status(:see_other)
    end
  end
end
