# frozen_string_literal: true

require "rails_helper"

# After a successful public submit the visitor stays on the page with its
# success_message, or — when the submit starts a journey — moves to the
# journey's next step. Locked inputs come from the run, not from after_submit
# page-to-page handoff (that setting is gone). Bound ids are re-checked on
# every render and submit; whatever the form posts for a bound slug is ignored.
RSpec.describe "Public page submission navigation and locked inputs", type: :request do
  include_context "as admin"
  include_context "student course association"

  def doc = Nokogiri::HTML(response.body)

  def reference_field(slug, entity, label_field)
    { "id" => "f_#{slug}", "property_slug" => slug, "source" => "entity", "label" => slug.humanize, "html_type" => "select",
      "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => entity.id.to_s, "label_field" => label_field } }
  end

  def text_field(slug)
    { "id" => "f_#{slug}", "property_slug" => slug, "source" => "entity", "label" => slug.humanize, "html_type" => "text" }
  end

  def launched_page(entity, fields:, form_settings: {}, **audiences)
    Current.set(customer: customer) do
      create(:page, customer: customer, entity: entity, launched: true, **audiences,
                    configuration: {
                      form_settings: form_settings,
                      metadata: { entity_id: entity.id, entity_name: entity.name },
                      pages: [{ "id" => "page_1", "fields" => fields }]
                    }.to_json)
    end
  end

  def bridge_page_for(**audiences)
    launched_page(bridge_entity, **audiences,
                  fields: [reference_field("student", student_entity, "full_name"), reference_field("course", course_entity, "code"),
                           text_field("status")],
                  form_settings: { modes: ["create"], inputs: [{ field: "student", entity_id: student_entity.id }] })
  end

  def student_page_for(**audiences)
    launched_page(student_entity, fields: [text_field("full_name")], **audiences,
                                  form_settings: { modes: ["create"], success_message: "Welcome, student!" })
  end

  def submit_path(page, **query)
    "/#{customer.id}/page/#{page.public_uuid}#{"?#{query.to_query}" if query.any?}"
  end

  def bridge_rows = EntityEntry.where(customer_id: customer.id, entity_id: bridge_entity.id)

  describe "success message on the same page" do
    it "flashes the page's form_settings.success_message and stays on the form" do
      sign_out admin
      student_page = student_page_for(audience_admin: false, audience_public: true)

      post submit_path(student_page), params: { entity: { full_name: "Grace" } }

      expect(EntityEntry.where(entity_id: student_entity.id, customer_id: customer.id).order(:id).last.data_json["full_name"]).to eq("Grace")
      expect(flash[:notice]).to eq("Welcome, student!")
      expect(response).to redirect_to(submit_path(student_page))
      expect(JourneyRun.count).to eq(0)
    end
  end

  describe "journey next step" do
    let!(:student_page) { student_journey_page }
    let!(:course_page) { course_journey_page }
    let!(:journey) { create(:journey, :launched, customer: customer) }

    it "opens the journey's next page with the new student locked in" do
      post submit_path(student_page, return_to: PageRendering::ENTITY_ENTRY_RETURN), params: { entity: { full_name: "Grace" } }

      grace = EntityEntry.where(entity_id: student_entity.id, customer_id: customer.id).order(:id).last
      expect(grace.data_json["full_name"]).to eq("Grace")
      location = Addressable::URI.parse(response.location)
      expect(location.path).to eq(new_admin_entity_entry_path(customer.id, bridge_entity))
      expect(location.query_values).to include("page" => course_page.id.to_s, "run" => be_present)
      expect(JourneyRun.find_by(token_digest: Digest::SHA256.hexdigest(location.query_values["run"]))).to have_attributes(
        customer_id: customer.id, user_id: admin.id, journey_id: journey.id
      )

      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("[data-role='locked-inputs']").text).to include("Student").and include("Grace")
      expect(doc.at_css("select[name='entity[student]']")).to be_nil
      expect(doc.at_css("select[name='entity[course]']")).to be_present
      expect(doc.at_css("input[type='hidden'][name='_run']")["value"]).to eq(location.query_values["run"])
    end

    it "saves the run's student and ignores a forged one on submit" do
      post submit_path(student_page, return_to: PageRendering::ENTITY_ENTRY_RETURN), params: { entity: { full_name: "Grace" } }
      token = Addressable::URI.parse(response.location).query_values["run"]
      grace = EntityEntry.where(entity_id: student_entity.id, customer_id: customer.id).order(:id).last
      other = create(:entity_entry, :with_data, customer: customer, entity: student_entity, entry_data: { "full_name" => "Bob" })

      expect do
        post submit_path(course_page, return_to: PageRendering::ENTITY_ENTRY_RETURN, page: course_page.id),
             params: { _run: token, entity: { student: other.id.to_s, course: math.id.to_s, status: "enrolled" } }
      end.to change(bridge_rows, :count).by(1)

      expect(bridge_rows.order(:id).last.data_json["student"].to_s).to eq(grace.id.to_s)
    end

    it "keeps a quick-add dialog submission in its frame, without starting a journey" do
      post submit_path(student_page, return_to: PageRendering::ENTITY_ENTRY_RETURN), params: { entity: { full_name: "Grace" } },
                                                                                       headers: { "Turbo-Frame" => Admin::Entities::QuickAddDialogComponent.frame_id(0) }

      grace = EntityEntry.where(entity_id: student_entity.id, customer_id: customer.id).order(:id).last
      expect(response.location).to include(admin_entity_entry_path(customer.id, student_entity, grace.id))
      expect(JourneyRun.where.not(journey_id: nil).count).to eq(0)
    end
  end

  describe "as an anonymous visitor" do
    before { sign_out admin }

    let!(:student_page) { student_journey_page(audience_admin: false, audience_public: true) }
    let!(:course_page) { course_journey_page(audience_admin: false, audience_public: true) }
    let!(:journey) { create(:journey, :launched, customer: customer, audience_admin: false, audience_public: true) }

    def start_journey
      post submit_path(student_page), params: { entity: { full_name: "Grace" } }
      Addressable::URI.parse(response.location).query_values["run"]
    end

    it "opens the next public page with the new student locked in" do
      token = start_journey
      expect(token).to be_present
      expect(JourneyRun.find_by(token_digest: Digest::SHA256.hexdigest(token)).user_id).to be_nil

      follow_redirect!

      expect(doc.at_css("[data-role='locked-inputs']").text).to include("Grace")
      expect(doc.at_css("select[name='entity[student]']")).to be_nil
    end

    it "ignores a forged student on submit" do
      token = start_journey
      grace = EntityEntry.where(entity_id: student_entity.id, customer_id: customer.id).order(:id).last

      post submit_path(course_page), params: { _run: token, entity: { student: student.id.to_s, course: math.id.to_s, status: "enrolled" } }

      expect(bridge_rows.order(:id).last.data_json["student"].to_s).to eq(grace.id.to_s)
    end

    it "only honours the run in the session that started it" do
      token = start_journey
      reset!

      get submit_path(course_page, run: token)

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("[data-role='locked-inputs']")).to be_nil
      expect(doc.at_css("select[name='entity[student]']")).to be_present
    end
  end

  describe "admin entry pages honour ?page=" do
    def student_create_page(name) = launched_page(student_entity, fields: [text_field("full_name")], form_settings: { modes: ["create"] }).tap { |p| p.update!(name: name) }

    let!(:older) { student_create_page("Older") }
    let!(:newest) { student_create_page("Newest") }

    def rendered_page_uuid = doc.at_css("form[action*='/page/']")["action"][%r{/page/([^/?]+)}, 1]

    it "renders the requested launched admin page of this entity" do
      get new_admin_entity_entry_path(customer.id, student_entity, page: older.id)
      expect(rendered_page_uuid).to eq(older.public_uuid)
    end

    it "falls back to the resolver for a page of another entity, tenant, audience or action" do
      foreign_customer = create(:customer)
      foreign = Current.set(customer: foreign_customer) { create(:page, customer: foreign_customer, entity: student_entity, launched: true) }
      update_only = launched_page(student_entity, fields: [text_field("full_name")], form_settings: { modes: ["update"] })
      public_only = launched_page(student_entity, fields: [text_field("full_name")], audience_admin: false, audience_public: true)
      course_page = launched_page(course_entity, fields: [text_field("code")])

      [foreign.id, update_only.id, public_only.id, course_page.id, "abc", "0"].each do |id|
        get new_admin_entity_entry_path(customer.id, student_entity, page: id)
        expect(rendered_page_uuid).to eq(newest.public_uuid)
      end
    end

    it "opens a bridge entity's entry form only through its requested page" do
      bridge_page = bridge_page_for

      get new_admin_entity_entry_path(customer.id, bridge_entity, page: bridge_page.id)
      expect(response).to have_http_status(:ok)
      expect(rendered_page_uuid).to eq(bridge_page.public_uuid)

      get new_admin_entity_entry_path(customer.id, bridge_entity)
      expect(response).to have_http_status(:not_found)

      get new_admin_entity_entry_path(customer.id, bridge_entity, page: older.id)
      expect(response).to have_http_status(:not_found)
    end

    it "keeps the run and the requested page when a submit is refused" do
      student_page = student_journey_page
      course_page = course_journey_page
      create(:journey, :launched, customer: customer)
      post submit_path(student_page, return_to: PageRendering::ENTITY_ENTRY_RETURN), params: { entity: { full_name: "Grace" } }
      token = Addressable::URI.parse(response.location).query_values["run"]

      post submit_path(course_page, return_to: PageRendering::ENTITY_ENTRY_RETURN, page: course_page.id),
           params: { _run: token, entity: { course: "", status: "enrolled" } }

      location = Addressable::URI.parse(response.location)
      expect(location.path).to eq(new_admin_entity_entry_path(customer.id, bridge_entity))
      expect(location.query_values).to include("page" => course_page.id.to_s, "run" => token)
      expect(bridge_rows.count).to eq(0)
    end
  end
end
