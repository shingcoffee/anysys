# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261123120000_remap_platform_owner_email")

RSpec.describe RemapPlatformOwnerEmail do
  def remap!
    described_class.remap(ActiveRecord::Base.connection)
  end

  def legacy_alias
    described_class::OLD_EMAILS.fetch(0)
  end

  def legacy_owner
    described_class::OLD_EMAILS.fetch(1)
  end

  def owner_with_legacy_email
    owner = find_or_create_platform_owner
    owner.update_columns(email: legacy_owner)
    owner
  end

  it "rewrites the pinned owner user onto lingercoffee@gmail.com" do
    owner = owner_with_legacy_email
    remap!
    expect(owner.reload.email).to eq("lingercoffee@gmail.com")
    expect(owner).to be_platform_owner
  end

  it "rewrites unconfirmed_email and customer contact" do
    owner = owner_with_legacy_email
    owner.update_columns(unconfirmed_email: legacy_alias)
    owner.customer.update_columns(contact: legacy_alias)

    remap!

    expect(owner.reload.unconfirmed_email).to eq("lingercoffee@gmail.com")
    expect(owner.customer.reload.contact).to eq("lingercoffee@gmail.com")
  end

  it "rewrites a suppression, and drops it when the new address already exists" do
    customer = create(:customer)
    Emails::Suppression.create!(customer_id: customer.id, email: legacy_owner, reason: "manual")
    Emails::Suppression.create!(customer_id: customer.id, email: "lingercoffee@gmail.com", reason: "manual")
    Emails::Suppression.create!(customer_id: nil, email: legacy_alias, reason: "hard_bounce")

    remap!

    expect(Emails::Suppression.where(customer_id: customer.id).pluck(:email)).to eq(["lingercoffee@gmail.com"])
    expect(Emails::Suppression.find_by(customer_id: nil).email).to eq("lingercoffee@gmail.com")
  end

  it "is idempotent when the owner is already on the new address" do
    owner = find_or_create_platform_owner
    expect(owner.email).to eq("lingercoffee@gmail.com")
    expect { remap! }.not_to change { owner.reload.email }
  end

  it "refuses to collapse two distinct user rows onto the same address" do
    owner_with_legacy_email
    create(:user, customer: create(:customer), email: legacy_alias)

    expect { remap! }.to raise_error(ActiveRecord::MigrationError, /Cannot remap 2 users/)
  end
end
