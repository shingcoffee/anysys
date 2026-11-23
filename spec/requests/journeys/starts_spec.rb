# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Journey start URL", type: :request do
  let(:customer) { create(:customer) }

  include_context "student course association"

  let!(:student_page) { student_journey_page(audience_public: true, audience_member: true) }

  def start_path(key) = "/#{customer.id}/journeys/#{key}"

  it "opens a launched public journey's first public page" do
    journey = create(:journey, :launched, customer: customer, audience_admin: false, audience_public: true)

    get start_path(journey.key)

    expect(response).to have_http_status(:see_other)
    expect(response.location).to end_with("/#{customer.id}/page/#{student_page.public_uuid}")
  end

  it "opens an admin journey's first page on the entries area" do
    journey = create(:journey, :launched, customer: customer)
    sign_in create(:user, :admin, customer: customer)

    get start_path(journey.key)

    expect(response).to have_http_status(:see_other)
    location = Addressable::URI.parse(response.location)
    expect(location.path).to eq(new_admin_entity_entry_path(customer.id, student_entity))
    expect(location.query_values).to eq("page" => student_page.id.to_s)
  end

  it "is unavailable for a draft, unknown or other tenant's journey" do
    draft = create(:journey, customer: customer, audience_public: true)
    foreign = create(:journey, :launched, audience_public: true)

    [draft.key, "nope", foreign.key].each do |key|
      get start_path(key)

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include(I18n.t("journeys.runtime.unavailable"))
    end
  end

  it "is unavailable when the visitor's audience isn't in the journey" do
    journey = create(:journey, :launched, customer: customer)

    get start_path(journey.key)

    expect(response).to have_http_status(:not_found)
  end

  it "sends an anonymous visitor on a member journey to sign in" do
    journey = create(:journey, :launched, customer: customer, audience_admin: false, audience_member: true)

    get start_path(journey.key)

    expect(response).to redirect_to(new_user_session_path)
  end

  it "doesn't route keys outside the action key format" do
    get "/#{customer.id}/journeys/Bad-Key"

    expect(response).to have_http_status(:not_found)
  end
end
