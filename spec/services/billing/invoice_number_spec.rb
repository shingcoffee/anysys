# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::InvoiceNumber do
  before { allow(Billing::Onboarding).to receive(:call) }

  it "allocates monotonically without depending on draft count" do
    customer = create(:customer)
    numbers = Billing::Invoice.transaction { 3.times.map { described_class.allocate!(customer_id: customer.id) } }
    expect(numbers).to eq((1..3).map { |n| "INV-#{customer.id}-#{n.to_s.rjust(5, '0')}" })
    expect(Billing::InvoiceSequence.find_by!(customer_id: customer.id).last_value).to eq(3)
    expect(Billing::Invoice.where(customer_id: customer.id)).to be_empty
  end

  it "honors a migration-backfilled maximum and keeps tenant sequences independent" do
    first, second = create_list(:customer, 2)
    Billing::InvoiceSequence.create!(customer_id: first.id, last_value: 123)
    a, b = Billing::Invoice.transaction do
      [described_class.allocate!(customer_id: first.id), described_class.allocate!(customer_id: second.id)]
    end
    expect(a).to end_with("00124")
    expect(b).to end_with("00001")
  end
end
