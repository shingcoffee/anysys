# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartNotification, type: :model do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other) { create(:customer) }
  let_it_be(:user) { create(:user, :member, customer: customer) }

  it "belongs to a customer and user" do
    record = build(:flowchart_notification, customer: customer, user: user)
    expect(record.customer).to eq(customer)
    expect(record.user).to eq(user)
  end

  it "requires customer_id and user_id" do
    record = described_class.new
    expect(record).not_to be_valid
    expect(record.errors[:customer_id]).to be_present
    expect(record.errors[:user_id]).to be_present
  end

  it "scopes by tenant" do
    mine = create(:flowchart_notification, customer: customer, user: user)
    create(:flowchart_notification, customer: other, user: create(:user, :member, customer: other))

    expect(described_class.for_customer(customer.id)).to contain_exactly(mine)
    expect(described_class.for_customer(customer.id).map(&:customer_id).uniq).to eq([customer.id])
  end

  it "optionally belongs to a page" do
    page = create(:page, customer: customer, launched: true)
    record = create(:flowchart_notification, customer: customer, user: user, page: page)
    expect(record.page).to eq(page)
  end
end
