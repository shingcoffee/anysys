# frozen_string_literal: true

require "rails_helper"

RSpec.describe People::ExpirePendingClaimsJob do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }

  def claim_for(owner, attrs = {})
    user = attrs[:user] || create(:user, :member, :unconfirmed, customer: owner)
    create(
      :people_pending_claim,
      customer: owner,
      user: user,
      entity_entry: attrs.fetch(:entity_entry, nil),
      created_user: attrs.fetch(:created_user, false),
      expires_at: attrs.fetch(:expires_at, 1.minute.ago)
    )
  end

  it "deletes expired claims" do
    stale = claim_for(customer, expires_at: 1.minute.ago)
    fresh = claim_for(customer, expires_at: 1.day.from_now)

    described_class.perform_now

    expect(People::PendingClaim.find_by(id: stale.id)).to be_nil
    expect(People::PendingClaim.find(fresh.id)).to eq(fresh)
  end

  it "destroys the unclaimed entry and unconfirmed user for an expired created_user claim" do
    user = create(:user, :member, :unconfirmed, customer: customer)
    entry = create(:entity_entry, customer: customer)
    claim = claim_for(customer, user: user, entity_entry: entry, created_user: true)

    described_class.perform_now

    expect(People::PendingClaim.find_by(id: claim.id)).to be_nil
    expect(EntityEntry.find_by(id: entry.id)).to be_nil
    expect(Authentication::User.find_by(id: user.id)).to be_nil
    expect(UsersRole.where(user_id: user.id)).to be_empty
  end

  it "keeps a user who confirmed since and still deletes the claim" do
    user = create(:user, :member, customer: customer)
    entry = create(:entity_entry, customer: customer)
    claim = claim_for(customer, user: user, entity_entry: entry, created_user: true)

    described_class.perform_now

    expect(People::PendingClaim.find_by(id: claim.id)).to be_nil
    expect(Authentication::User.find(user.id)).to eq(user)
    expect(EntityEntry.find(entry.id)).to eq(entry)
  end

  it "keeps an entry that has been linked" do
    user = create(:user, :member, :unconfirmed, customer: customer)
    other_user = create(:user, :member, customer: customer)
    entry = create(:entity_entry, customer: customer, user: other_user)
    claim = claim_for(customer, user: user, entity_entry: entry, created_user: true)

    described_class.perform_now

    expect(People::PendingClaim.find_by(id: claim.id)).to be_nil
    expect(entry.reload.user_id).to eq(other_user.id)
    expect(Authentication::User.find_by(id: user.id)).to be_nil
  end

  it "leaves unexpired claims alone" do
    user = create(:user, :member, :unconfirmed, customer: customer)
    entry = create(:entity_entry, customer: customer)
    claim = claim_for(
      customer,
      user: user,
      entity_entry: entry,
      created_user: true,
      expires_at: 1.day.from_now
    )

    described_class.perform_now

    expect(People::PendingClaim.find(claim.id)).to eq(claim)
    expect(EntityEntry.find(entry.id)).to eq(entry)
    expect(Authentication::User.find(user.id)).to eq(user)
  end

  it "only deletes the claim when created_user is false" do
    user = create(:user, :member, :unconfirmed, customer: customer)
    entry = create(:entity_entry, customer: customer)
    claim = claim_for(customer, user: user, entity_entry: entry, created_user: false)

    described_class.perform_now

    expect(People::PendingClaim.find_by(id: claim.id)).to be_nil
    expect(EntityEntry.find(entry.id)).to eq(entry)
    expect(Authentication::User.find(user.id)).to eq(user)
  end

  it "never lets one tenant's expiry touch another tenant's rows" do
    user_a = create(:user, :member, :unconfirmed, customer: customer)
    user_b = create(:user, :member, :unconfirmed, customer: other)
    entry_b = create(:entity_entry, customer: other)
    claim_a = claim_for(customer, user: user_a, entity_entry: entry_b, created_user: true)
    claim_b = claim_for(
      other,
      user: user_b,
      entity_entry: entry_b,
      created_user: true,
      expires_at: 1.day.from_now
    )

    described_class.perform_now

    expect(People::PendingClaim.find_by(id: claim_a.id)).to be_nil
    expect(Authentication::User.find_by(id: user_a.id)).to be_nil
    expect(EntityEntry.find(entry_b.id)).to eq(entry_b)
    expect(People::PendingClaim.find(claim_b.id)).to eq(claim_b)
    expect(Authentication::User.find(user_b.id)).to eq(user_b)
  end

  it "is safe to run again after the expired rows are already gone" do
    user = create(:user, :member, :unconfirmed, customer: customer)
    entry = create(:entity_entry, customer: customer)
    claim_for(customer, user: user, entity_entry: entry, created_user: true)

    described_class.perform_now
    expect { described_class.perform_now }.not_to raise_error

    expect(People::PendingClaim.expired).to be_empty
    expect(EntityEntry.find_by(id: entry.id)).to be_nil
    expect(Authentication::User.find_by(id: user.id)).to be_nil
  end

  it "registers a daily recurring entry that names the job class" do
    config = YAML.safe_load_file(Rails.root.join("config/recurring.yml"))
    entry = config.fetch("production").fetch("people_expire_pending_claims")

    expect(entry.fetch("class")).to eq("People::ExpirePendingClaimsJob")
    expect(entry.fetch("queue")).to eq("default")
    expect(entry.fetch("schedule")).to match(/every day/)
  end
end
