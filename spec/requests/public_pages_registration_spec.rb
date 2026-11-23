# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public page register_member submission", type: :request do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:entity) { build_student_entity(customer) }
  let(:page) do
    build_public_registration_page(customer: customer, entity: entity)
  end
  let(:url) { "/#{customer.id}/page/#{page.public_uuid}" }

  def submit(email)
    post url, params: { identity: { first_name: "Pat", last_name: "Lee", email: email } }
    {
      status: response.status,
      location: response.redirect_url,
      notice: flash[:notice],
      alert: flash[:alert]
    }
  end

  def recompile_bound_flowchart!(bound)
    flowchart = Flowchart.find(bound.flowchart_id)
    flowchart.update_column(:activity, ActivityGenerator.new(flowchart).generate)
  end

  before do
    stub_member_quota_allow!
    enable_authentication_signup!(customer)
    enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)
    page
    recompile_bound_flowchart!(page)
  end

  it "returns the same redirect and flash for a new email, an existing member, and another tenant's email" do
    member = create(:user, :member, customer: customer, email: "already@example.com")
    foreign = create(:user, :member, customer: other_customer, email: "other-tenant@example.com")

    new_response = nil
    expect {
      new_response = submit("fresh-reg@example.com")
    }.to change(EntityEntry, :count).by(1)
      .and change(Authentication::User, :count).by(1)
    new_email_counts = [EntityEntry.count, Authentication::User.count]

    existing_response = submit(member.email)
    existing_counts = [EntityEntry.count, Authentication::User.count]
    expect(existing_counts).to eq(new_email_counts)

    foreign_response = submit(foreign.email)
    foreign_counts = [EntityEntry.count, Authentication::User.count]
    expect(foreign_counts).to eq(existing_counts)

    expect(new_response).to eq(existing_response)
    expect(existing_response).to eq(foreign_response)
    expect(new_response[:status]).to eq(302)
    expect(new_response[:location]).to end_with(url)
    expect(new_response[:notice]).to eq(I18n.t("public_views.flash.outcomes.registration_pending"))
    expect(new_response[:alert]).to be_nil

    expect(new_email_counts[0]).to eq(existing_counts[0])
    expect(new_email_counts[1]).to eq(existing_counts[1])
    expect(existing_counts).to eq(foreign_counts)

    created = Authentication::User.find_by_normalized_email("fresh-reg@example.com")
    entry = EntityEntry.find_by!(entity: entity, customer: customer)
    expect(entry.user_id).to be_nil
    expect(entry.data_json).to include(
      "first_name" => "Pat", "last_name" => "Lee", "email" => "fresh-reg@example.com"
    )
    expect(People::PendingClaim.find_by!(user_id: created.id)).to have_attributes(
      entity_entry_id: entry.id, created_user: true
    )
    expect(People::PendingClaim.find_by!(user_id: member.id)).to have_attributes(
      entity_entry_id: nil, created_user: false
    )
    expect(People::PendingClaim.find_by(user_id: foreign.id)).to be_nil
  end

  it "pads new, existing and other-tenant addresses to the same minimum duration" do
    member = create(:user, :member, customer: customer, email: "already@example.com")
    foreign = create(:user, :member, customer: other_customer, email: "other-tenant@example.com")
    expect(Authentication::UniformTiming).to receive(:pad).with(kind_of(Numeric)).exactly(3).times

    ["padded@example.com", member.email, foreign.email].each { |email| submit(email) }
  end

  it "answers a repeat submission and a full quota like a new email, keeping the first claim" do
    first = submit("twice@example.com")
    created = Authentication::User.find_by_normalized_email("twice@example.com")
    claim = People::PendingClaim.find_by!(user_id: created.id)

    repeat = nil
    expect { repeat = submit("twice@example.com") }
      .not_to change { [EntityEntry.count, Authentication::User.count, People::PendingClaim.count] }
    expect(claim.reload).to have_attributes(created_user: true, entity_entry_id: claim.entity_entry_id)

    deny = instance_double(Billing::Quota::Guard::Result, allowed?: false, message: "full")
    allow(Billing::Quota::Guard).to receive(:check).and_return(deny)
    full = nil
    expect { full = submit("quota-full@example.com") }
      .not_to change { [EntityEntry.count, Authentication::User.count, People::PendingClaim.count] }

    expect(repeat).to eq(first)
    expect(full).to eq(first)

    created.confirm
    expect(People::Claim.complete!(created)).to be_nil
    expect(EntityEntry.find(claim.entity_entry_id).user_id).to eq(created.id)
  end
end
