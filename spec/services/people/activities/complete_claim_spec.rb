# frozen_string_literal: true

require "rails_helper"

RSpec.describe People::Activities::CompleteClaim do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:entity) do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    create(:entity, customer: customer, name: "Student", extended_model: person_model)
  end
  let(:entry) { create(:entity_entry, entity: entity, customer: customer) }
  let(:user) { create(:user, :member, customer: customer) }
  let(:continuation) { { "action_key" => "enroll", "prefill" => { "course" => "12" } } }

  def record!(attrs = {})
    People::Claim.record!(
      user: attrs.fetch(:user, user),
      entry: attrs.fetch(:entry, entry),
      continuation: attrs.fetch(:continuation, continuation),
      created_user: attrs.fetch(:created_user, true)
    )
  end

  def complete(for_user = user)
    described_class.call(user: for_user)
  end

  it "links the entry and writes one person.claimed audit row with the user as actor" do
    record!

    path = complete

    expect(path).to eq("/#{customer.id}/actions/enroll?prefill[course]=12")
    expect(entry.reload.user_id).to eq(user.id)
    events = Authentication::Event.where(event: "person.claimed")
    expect(events.count).to eq(1)
    expect(events.last).to have_attributes(user_id: user.id, customer_id: customer.id, event: "person.claimed")
    expect(events.last.metadata.stringify_keys).to include(
      "entry_id" => entry.id, "entity_id" => entity.id, "linked_user_id" => user.id
    )
    expect(People::PendingClaim.find_by(user_id: user.id)).to be_nil
  end

  it "skips an entry that was linked to someone else and still consumes the claim" do
    other = create(:user, :member, customer: customer)
    record!
    People::Link.link!(entry: entry, user_id: other.id, actor: other)

    expect(complete).to eq("/#{customer.id}/actions/enroll?prefill[course]=12")
    expect(entry.reload.user_id).to eq(other.id)
    expect(Authentication::Event.where(event: "person.claimed").count).to eq(0)
    expect(People::PendingClaim.find_by(user_id: user.id)).to be_nil
  end

  it "returns the continuation when the entry was deleted and the FK was nullified" do
    claim = record!
    entry.destroy!
    expect(claim.reload.entity_entry_id).to be_nil

    expect(complete).to eq("/#{customer.id}/actions/enroll?prefill[course]=12")
    expect(People::PendingClaim.find_by(id: claim.id)).to be_nil
  end

  it "returns nil for an expired claim and leaves it for the expiry job" do
    claim = record!
    claim.update_columns(expires_at: 1.minute.ago)

    expect(complete).to be_nil
    expect(People::PendingClaim.find(claim.id)).to eq(claim)
    expect(entry.reload.user_id).to be_nil
  end

  it "never completes a claim for a user of another tenant" do
    claim = record!
    stranger = create(:user, :member, customer: other_customer)

    expect(complete(stranger)).to be_nil
    expect(People::PendingClaim.find(claim.id)).to eq(claim)
    expect(entry.reload.user_id).to be_nil
  end

  it "ignores a claim whose customer_id differs from the user's" do
    claim = record!
    claim.update_columns(customer_id: other_customer.id)

    expect(complete).to be_nil
    expect(People::PendingClaim.find(claim.id).customer_id).to eq(other_customer.id)
    expect(entry.reload.user_id).to be_nil
  end

  it "returns nil on a second complete!" do
    record!

    expect(complete).to be_present
    expect(complete).to be_nil
  end

  it "consumes a claim whose continuation action key is invalid and returns a nil path" do
    record!(continuation: { "action_key" => "Not Valid", "prefill" => { "course" => "12" } })

    expect(complete).to be_nil
    expect(entry.reload.user_id).to eq(user.id)
    expect(People::PendingClaim.find_by(user_id: user.id)).to be_nil
  end
end
