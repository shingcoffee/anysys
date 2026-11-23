# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Onboarding do
  it "reports missing configuration without creating settings or plans" do
    customer = create(:customer)
    expect { expect(described_class.call(customer).reason).to eq(:fallback_configuration_invalid) }
      .not_to change(Billing::Settings, :count)
    expect(Billing::Plan.count).to eq(0)
  end

  it "uses a permanent request identity and restores the caller's tenant context" do
    customer = create(:customer)
    other = create(:customer)
    Billing::StandardPlans.seed!
    Current.set(customer: other) do
      first = described_class.call(customer)
      Billing::Activities::FinalizeInvoice.call(invoice: first.invoice)
      expect(first.subscription.reload.status).to eq("active")
      Billing::Activities::CancelSubscription.call(subscription: first.subscription, immediately: true)
      expect(described_class.call(customer).status).to eq(:unchanged)
      expect(Current.customer).to eq(other)
      expect(Billing::Subscription.where(customer_id: customer.id).count).to eq(1)
    end
  end
end
