require "rails_helper"

RSpec.describe Payments::Activities::CancelSubscription do
  let_it_be(:customer) { create(:customer) }
  let(:user)         { create(:user, customer: customer) }
  let(:subscription) { create_subscription }

  before { Current.customer = customer }

  def create_subscription(**overrides)
    create(:payment_subscription,
           { provider: "wechat_pay", external_ref: "sub-1", plan_name: "Gold",
             amount: 10.00, cycle: "monthly", status: "active",
             next_charge_at: 1.day.from_now }.merge(overrides))
  end

  it "calls the gateway and marks the subscription cancelled" do
    allow(Payments::Gateway).to receive(:cancel_subscription)
      .with(customer: customer, subscription: subscription).and_return(true)

    result = described_class.call(customer: customer, subscription: subscription)

    expect(Payments::Gateway).to have_received(:cancel_subscription)
    expect(result.status).to eq("cancelled")
    expect(subscription.reload.status).to eq("cancelled")
  end

  it "does not call the gateway for a billing mandate" do
    mandate = create_subscription(managed_by: "billing", next_charge_at: nil, external_ref: "billing-pm-1")
    expect(Payments::Gateway).not_to receive(:cancel_subscription)

    expect {
      described_class.call(customer: customer, subscription: mandate)
    }.to raise_error(Payments::Errors::Error, /billing mandates/)
    expect(mandate.reload.status).to eq("active")
  end

  it "propagates gateway errors and leaves subscription active" do
    allow(Payments::Gateway).to receive(:cancel_subscription)
      .and_raise(Payments::Errors::ApiError.new("boom"))

    expect {
      described_class.call(customer: customer, subscription: subscription)
    }.to raise_error(Payments::Errors::ApiError)

    expect(subscription.reload.status).to eq("active")
  end

  describe "card-recurring token detach" do
    let(:payment_method) do
      create(:payment_method,
             customer:              customer,
             user:                  user,
             provider:              "stripe",
             psp_customer_id:       "cus_123",
             psp_payment_method_id: "pm_visa_1",
             status:                "active")
    end

    let(:card_subscription) do
      create_subscription(provider: "stripe", external_ref: "card-sub-1", plan_name: "Card Plan",
                          amount: 20.00, payment_method: payment_method)
    end

    before do
      allow(Payments::Gateway).to receive(:cancel_subscription).and_return(status: :cancelled)
      allow(Payments::Gateway).to receive(:detach_token).and_return(status: :removed)
    end

    it "detaches the token and marks the PaymentMethod removed when no other active subscription uses it" do
      described_class.call(customer: customer, subscription: card_subscription)

      expect(Payments::Gateway).to have_received(:detach_token).with(
        customer: customer, payment_method: payment_method
      )
      expect(payment_method.reload.status).to eq("removed")
    end

    it "does NOT detach the token when detach_orphaned_token is false" do
      described_class.call(customer: customer, subscription: card_subscription, detach_orphaned_token: false)

      expect(Payments::Gateway).not_to have_received(:detach_token)
      expect(payment_method.reload.status).to eq("active")
    end

    it "does NOT detach the token when another active subscription references it" do
      create_subscription(provider: "stripe", external_ref: "card-sub-2", plan_name: "Another Plan",
                          amount: 15.00, payment_method: payment_method)

      described_class.call(customer: customer, subscription: card_subscription)

      expect(Payments::Gateway).not_to have_received(:detach_token)
      expect(payment_method.reload.status).to eq("active")
    end

    it "does not raise when token detach fails (best-effort)" do
      allow(Payments::Gateway).to receive(:detach_token)
        .and_raise(Payments::Errors::ApiError.new("network error"))

      expect {
        described_class.call(customer: customer, subscription: card_subscription)
      }.not_to raise_error

      expect(card_subscription.reload.status).to eq("cancelled")
    end
  end
end
