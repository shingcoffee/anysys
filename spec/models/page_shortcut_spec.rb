# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageShortcut, type: :model do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:page) { create(:page, :for_member, :for_public, customer: customer, launched: true) }
  let(:attributes) { { customer_id: customer.id, path: "/join", target_type: "Page", target_id: page.id } }

  after { Current.reset }

  it "has an explicit tenant scope independent of Current and supports target preloading" do
    mine = described_class.create!(attributes)
    described_class.create!(attributes.merge(customer_id: other_customer.id))
    Current.customer = other_customer

    expect(described_class.for_customer(customer.id).includes(:target).to_a).to eq([mine])
    expect(mine.target).to eq(page)
  end

  it "does not fill an omitted customer from Current" do
    Current.customer = customer
    expect { described_class.create!(attributes.except(:customer_id)) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "enforces unique paths per tenant at the database layer" do
    described_class.create!(attributes)
    expect { described_class.create!(attributes) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { described_class.create!(attributes.merge(customer_id: other_customer.id)) }.not_to raise_error
  end

  it "enforces the allowlist and leading slash at the database layer" do
    %w[Customer Kernel].each do |type|
      record = described_class.new(attributes.merge(target_type: type))
      expect(record.target).to be_nil
      expect { record.save! }.to raise_error(ActiveRecord::StatementInvalid)
    end
    expect { described_class.create!(attributes.merge(path: "join")) }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "keeps missing-target mappings preloadable and removable" do
    shortcut = described_class.create!(attributes.merge(target_id: 999999999))
    expect(described_class.includes(:target).find(shortcut.id).target).to be_nil
    expect { shortcut.destroy! }.not_to change(Page, :count)
  end
end
