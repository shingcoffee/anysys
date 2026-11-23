# frozen_string_literal: true

require "rails_helper"

# After Settings / Member saves a row action, the member entity index renders
# a button to /:cid/actions/<key>?prefill[<field>]=<row id>.
RSpec.describe "Member surface row actions", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:member) { create(:user, :member, customer: customer) }

  let!(:course) do
    create(:entity, customer: customer, name: "Course",
           property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
  end
  let!(:row) do
    create(:entity_entry, :with_data, customer: customer, entity: course, entry_data: { "title" => "Algebra" })
  end
  let(:surface_key) { "entity_#{course.id}" }

  before do
    create(:page, :launched, :member_only, customer: customer, action_key: "enroll")
    setting = Member::SurfaceSetting.for_customer_surface(
      customer_id: customer.id, surface_key: surface_key
    )
    setting.source_key = "entities"
    setting.enabled = true
    setting.write_overlay(row_action_key: "enroll", row_action_field: "course", row_action_label: "Enroll")
    setting.save!
    sign_in member
  end

  it "shows the row action button linking to the action router with the row prefilled" do
    get "/#{customer.id}/member/#{surface_key}"

    expect(response).to have_http_status(:ok)
    href = Pages::ActionLink.path(
      customer_id: customer.id, action_key: "enroll", prefill: { "course" => row.id }
    )
    expect(response.body).to include(href)
    expect(Capybara.string(response.body)).to have_link("Enroll", href: href)
  end

  it "does not show a row action for another tenant's member" do
    other = create(:customer)
    foreign = create(:user, :member, customer: other)
    sign_in foreign

    get "/#{other.id}/member/#{surface_key}"
    expect(response).to have_http_status(:not_found)
  end
end
