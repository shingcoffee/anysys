# frozen_string_literal: true

require "rails_helper"

# Public pages reached through the action router carry a signed continuation
# so registration can resume the same action as a member (§3.10.5).
RSpec.describe "Public page continuation", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:action_key) { "enroll" }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" }
    ].to_json)
  end

  def form_fields
    [ { "id" => "name", "property_slug" => "name", "html_type" => "text",
        "source" => "entity", "label" => "Name" } ]
  end

  def build_page(*traits, key: action_key)
    config = {
      "metadata" => { "entity_id" => entity.id, "entity_name" => entity.name },
      "pages" => [ { "id" => "p1", "fields" => form_fields } ]
    }
    Current.set(customer: customer) do
      create(:page, *traits, :launched, customer: customer, entity: entity,
             action_key: key, configuration: config.to_json)
    end
  end

  def continuation_input
    Nokogiri::HTML(response.body).at_css('input[name="_continuation"]')
  end

  describe "GET" do
    it "renders the hidden _continuation field only when the action router supplied a valid token" do
      public_page = build_page(:public_only)
      build_page(:member_only)

      get "/#{customer.id}/actions/#{action_key}", params: { prefill: { course: "12" } }
      expect(response).to have_http_status(:see_other)

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(continuation_input).to be_present
      expect(Pages::Continuation.verify(continuation_input["value"])).to eq(
        action_key: action_key,
        prefill: { "course" => "12" }
      )

      get "/#{customer.id}/page/#{public_page.public_uuid}"
      expect(response).to have_http_status(:ok)
      expect(continuation_input).to be_nil
    end

    it "omits the hidden field for a tampered continuation" do
      page = build_page(:public_only, key: "intake")
      token = Pages::Continuation.sign(action_key: "intake", prefill: { "course" => "1" })

      get "/#{customer.id}/page/#{page.public_uuid}", params: { continuation: "#{token}x" }

      expect(response).to have_http_status(:ok)
      expect(continuation_input).to be_nil
    end
  end

  describe "POST" do
    let!(:page) { build_page(:public_only, key: "intake") }

    it "submits successfully when _continuation is tampered" do
      expect {
        post "/#{customer.id}/page/#{page.public_uuid}", params: {
          entity: { name: "Ada" },
          _continuation: "tampered-token"
        }
      }.to change { EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count }.by(1)

      expect(response).to have_http_status(:redirect)
    end

    it "submits successfully when a valid _continuation is posted and hands it to the bound flowchart" do
      bind_page_flowchart(page, body: <<~RUBY)
        ctx[:model].data_json = ctx[:model].data_json.merge("name" => ctx[:continuation][:action_key])
        ctx[:model].save!
        true
      RUBY
      token = Pages::Continuation.sign(action_key: "enroll", prefill: { "course" => "12" })

      expect {
        post "/#{customer.id}/page/#{page.public_uuid}", params: {
          entity: { name: "Ada" },
          _continuation: token
        }
      }.to change { EntityEntry.where(customer_id: customer.id, entity_id: entity.id).count }.by(1)

      expect(response).to have_http_status(:redirect)
      expect(EntityEntry.where(entity_id: entity.id).sole.data_json).to include("name" => "enroll")
    end
  end
end
