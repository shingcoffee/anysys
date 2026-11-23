# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Activities::ApplyCoupon do
  let(:subscription) { create(:billing_subscription) }
  let(:coupon) { create(:billing_coupon, duration: "once") }

  it "starts duration at redemption, independently of past free/paid history" do
    invoice = Billing::Activities::GenerateInvoice.call(subscription: subscription, purpose: :initial,
      idempotency_key: "past-free", period_start: subscription.current_period_start, period_end: subscription.current_period_end,
      terms_snapshot: Billing::PlanChangePolicy.invoice_terms(subscription.plan_snapshot.merge("amount_cents" => 0), due_at: Time.current))
    Billing::Activities::FinalizeInvoice.call(invoice: invoice)
    expect(described_class.call(subscription: subscription, coupon: coupon).status).to eq(:applied)
    expect(subscription.coupon_redemption.cycles_used).to eq(0)
    expect(coupon.reload.times_redeemed).to eq(1)
    expect(described_class.call(subscription: subscription, coupon: coupon).status).to eq(:unchanged)
    expect(coupon.reload.times_redeemed).to eq(1)
  end

  it "never reserves replacement inventory" do
    described_class.call(subscription: subscription, coupon: coupon)
    replacement = create(:billing_coupon)
    expect(described_class.call(subscription: subscription, coupon: replacement).reason).to eq(:already_applied)
    expect(replacement.reload.times_redeemed).to eq(0)
  end

  it "snapshots terms so archival and catalog expiry cannot revoke accepted benefit" do
    described_class.call(subscription: subscription, coupon: coupon)
    terms = subscription.coupon_redemption.terms_snapshot
    Billing::Catalog::ArchiveCoupon.call(coupon: coupon)
    expect(subscription.coupon_redemption.reload.terms_snapshot).to eq(terms)
    expect(coupon.reload.redeemable?).to be(false)
  end
end
