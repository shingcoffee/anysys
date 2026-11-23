# frozen_string_literal: true

require "rails_helper"

# A generated public sign-up journey: the visitor registers as a passwordless
# member on the person entity's public page, and once they confirm their email
# the claim continues on the member page the journey finishes on.
RSpec.describe "Public sign-up journey", type: :request do
  let(:customer) { create(:customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:domain) { create(:entity_domain, customer: customer, name: "School") }
  let(:student_entity) do
    create(:entity, customer: customer, name: "Student", display_label: "Student", extended_model: person_model,
                    property_schema: [{ "name" => "Phone", "name_slug" => "phone", "html_type" => "text" }].to_json)
  end
  let(:note_entity) do
    create(:entity, customer: customer, name: "Note", display_label: "Note", property_schema: [
      { "name" => "Student", "name_slug" => "student", "html_type" => "select", "type" => "EntityReference",
        "entity_id" => student_entity.id.to_s },
      { "name" => "Body", "name_slug" => "body", "html_type" => "text" }
    ].to_json)
  end
  let(:generated) do
    Journeys::Activities::Generate.call(customer: customer, domain_id: domain.id, candidate_key: "public-#{note_entity.id}")
  end
  let(:signup_page) { Page.find_by!(customer_id: customer.id, action_key: "signup_new_note") }
  let(:identity) { { first_name: "Pat", last_name: "Lee", email: "pat@example.com" } }

  before do
    stub_member_quota_allow!
    enable_authentication_signup!(customer)
    [student_entity, note_entity].each { |entity| EntityDomains::Memberships.place!(entity, domain) }
    generated.journey.update!(status: :launched)
  end

  def sign_up = post("/#{customer.id}/page/#{signup_page.public_uuid}", params: { identity: identity, entity: { phone: "555-0100" } })

  it "registers the visitor and continues on the member page once they confirm their email" do
    expect { sign_up }.to change(Authentication::User, :count).by(1)
    expect(flash[:notice]).to eq(I18n.t("public_views.flash.outcomes.registration_pending"))

    user = Authentication::User.find_by_normalized_email("pat@example.com")
    entry = EntityEntry.find_by!(customer_id: customer.id, entity_id: student_entity.id)
    expect(entry.data_json).to include("phone" => "555-0100", "email" => "pat@example.com")
    expect(People::PendingClaim.find_by!(user_id: user.id).continuation).to eq("action_key" => "member_new_note", "prefill" => {})

    user.confirm
    expect(People::Claim.complete!(user)).to eq("/#{customer.id}/actions/member_new_note")
    expect(entry.reload.user_id).to eq(user.id)
  end

  it "keeps a signed continuation the visitor brought over the journey's" do
    token = Pages::Continuation.sign(action_key: "elsewhere", prefill: {})
    post "/#{customer.id}/page/#{signup_page.public_uuid}", params: { identity: identity, _continuation: token }

    user = Authentication::User.find_by_normalized_email("pat@example.com")
    expect(People::PendingClaim.find_by!(user_id: user.id).continuation).to include("action_key" => "elsewhere")
  end

  it "parks no continuation once the journey is offline" do
    generated.journey.update!(status: :draft)
    sign_up

    user = Authentication::User.find_by_normalized_email("pat@example.com")
    expect(People::PendingClaim.find_by!(user_id: user.id).continuation).to be_blank
  end
end
