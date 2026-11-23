# frozen_string_literal: true

require "rails_helper"

# Prefill is display-only (§3.2.5 / §3.9): query values that survive
# Pages::Prefill.values appear as initial field values. Submission still
# uses posted params only — prefill grants nothing.
RSpec.describe "Page prefill on audience surfaces", type: :request do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:member) { create(:user, :member, customer: customer) }
  let(:admin) { create(:user, :admin, customer: customer) }

  let(:course) do
    create(:entity, customer: customer, name: "Course",
           property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
  end
  let(:enroll_entity) do
    create(:entity, customer: customer, name: "EnrollmentForm", property_schema: [
      { "name" => "Course", "name_slug" => "course", "type" => Entity::ENTITY_REFERENCE_TYPE,
        "entity_id" => course.id, "html_type" => "select" },
      { "name" => "Notes", "name_slug" => "notes", "html_type" => "text" },
      { "name" => "Internal", "name_slug" => "internal_note", "html_type" => "text",
        "visibility" => { "admin" => true, "member" => false, "public" => false } }
    ].to_json)
  end

  let(:own_course) { create(:entity_entry, :with_data, entity: course, customer: customer, entry_data: { "title" => "Algebra" }) }
  let(:foreign_course) do
    foreign_entity = create(:entity, customer: other_customer, name: "Course",
                            property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    create(:entity_entry, :with_data, entity: foreign_entity, customer: other_customer, entry_data: { "title" => "Foreign" })
  end

  let(:action_key) { "enroll" }

  def page_fields
    [
      { "id" => "course", "property_slug" => "course", "html_type" => "select", "source" => "entity",
        "label" => "Course",
        "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => course.id.to_s,
                               "label_field" => "title" } },
      { "id" => "notes", "property_slug" => "notes", "html_type" => "text", "source" => "entity",
        "label" => "Notes" },
      { "id" => "internal_note", "property_slug" => "internal_note", "html_type" => "text", "source" => "entity",
        "label" => "Internal" }
    ]
  end

  def build_page(*traits, key: action_key)
    config = {
      "metadata" => { "entity_id" => enroll_entity.id, "entity_name" => enroll_entity.name },
      "pages" => [{ "id" => "p1", "fields" => page_fields }]
    }
    Current.set(customer: customer) do
      create(:page, *traits, :launched, customer: customer, entity: enroll_entity,
             action_key: key, configuration: config.to_json)
    end
  end

  def selected_option(value)
    Nokogiri::HTML(response.body).at_css(%(option[value="#{value}"][selected]))
  end

  def notes_input
    Nokogiri::HTML(response.body).at_css('input[name="entity[notes]"]')
  end

  let!(:member_page) { build_page(:member_only) }
  let!(:public_page) { build_page(:public_only) }
  let!(:admin_page) { build_page }

  describe "GET member enroll page" do
    before { sign_in member }

    it "preselects an in-scope course from ?prefill[course]=" do
      get "/#{customer.id}/member/pages/#{member_page.id}", params: { prefill: { course: own_course.id } }

      expect(response).to have_http_status(:ok)
      expect(selected_option(own_course.id)).to be_present
    end

    it "ignores another tenant's course id" do
      get "/#{customer.id}/member/pages/#{member_page.id}",
          params: { prefill: { course: foreign_course.id } }

      expect(response).to have_http_status(:ok)
      expect(selected_option(foreign_course.id)).to be_nil
      expect(Nokogiri::HTML(response.body).at_css(%(option[value="#{foreign_course.id}"]))).to be_nil
    end

    it "never renders a prefilled hidden field's value" do
      secret = "hidden-prefill-#{SecureRandom.hex(8)}"
      get "/#{customer.id}/member/pages/#{member_page.id}",
          params: { prefill: { internal_note: secret, notes: "ok" } }

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('input[name="entity[internal_note]"]')).to be_nil
      expect(doc.css("input, textarea, option").map { |node| node["value"] }).not_to include(secret)
      expect(notes_input["value"]).to eq("ok")
    end

    it "HTML-escapes a prefill value in the rendered input" do
      get "/#{customer.id}/member/pages/#{member_page.id}",
          params: { prefill: { notes: '<script>alert(1)</script>' } }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(notes_input["value"]).to eq('<script>alert(1)</script>')
      expect(response.body).to include("value=\"&lt;script&gt;alert(1)&lt;/script&gt;\"")
    end
  end

  describe "GET admin entry form" do
    before { sign_in admin }

    it "preselects an in-scope course from ?prefill[course]=" do
      get new_admin_entity_entry_path(customer.id, enroll_entity), params: { prefill: { course: own_course.id } }

      expect(response).to have_http_status(:ok)
      expect(selected_option(own_course.id)).to be_present
    end
  end

  describe "POST without the prefilled value" do
    let!(:submittable) { build_page(:public_only, key: "intake") }

    it "does not persist a query prefill that was not posted (prefill grants nothing)" do
      get "/#{customer.id}/page/#{submittable.public_uuid}",
          params: { prefill: { notes: "from-query", course: own_course.id } }
      expect(response).to have_http_status(:ok)
      expect(notes_input["value"]).to eq("from-query")

      expect {
        post "/#{customer.id}/page/#{submittable.public_uuid}"
      }.to change { EntityEntry.where(customer_id: customer.id, entity_id: enroll_entity.id).count }.by(1)

      entry = EntityEntry.where(customer_id: customer.id, entity_id: enroll_entity.id).order(:id).last
      expect(entry.data_json).not_to include("from-query")
      expect(entry.data_json["course"]).not_to eq(own_course.id.to_s)
    end
  end

  describe "GET via the action router" do
    it "lands on the public surface with the prefill applied" do
      get "/#{customer.id}/actions/#{action_key}", params: { prefill: { course: own_course.id } }

      expect(response).to have_http_status(:see_other)
      uri = URI.parse(response.location)
      expect(uri.path).to eq("/#{customer.id}/page/#{public_page.public_uuid}")
      query = Rack::Utils.parse_nested_query(uri.query.to_s)
      expect(query.dig("prefill", "course")).to eq(own_course.id.to_s)
      expect(query["continuation"]).to be_present

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(selected_option(own_course.id)).to be_present
    end
  end
end
