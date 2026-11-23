# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Discounts do
  let(:subscription) { create(:billing_subscription) }

  def invoice(key, purpose: :renewal, amount: 9900)
    Billing::Activities::GenerateInvoice.call(subscription: subscription, purpose: purpose,
      idempotency_key: key, period_start: subscription.current_period_end, period_end: subscription.current_period_end + 1.month,
      terms_snapshot: Billing::PlanChangePolicy.invoice_terms(subscription.plan_snapshot.merge("amount_cents" => amount), due_at: subscription.current_period_end)
        .merge("billing_anchor_day" => subscription.billing_anchor_day, "billing_anchor_month" => subscription.billing_anchor_month),
      extra_line_items: purpose == :proration ? [{ description: "Accepted change", amount_cents: 500, unit_amount_cents: 500, kind: "proration", quantity: 1 }] : [])
  end

  it "counts only redemption-relative positive recurring cycles and never consumes twice" do
    coupon = create(:billing_coupon, :repeating, duration_in_cycles: 2, percent_off: 100)
    Billing::Activities::ApplyCoupon.call(subscription: subscription, coupon: coupon)
    redemption = subscription.coupon_redemption
    Billing::Activities::FinalizeInvoice.call(invoice: invoice("free-cycle", amount: 0))
    Billing::Activities::FinalizeInvoice.call(invoice: invoice("proration", purpose: :proration))
    expect(redemption.reload.cycles_used).to eq(0)
    first = invoice("first-cycle")
    Billing::Activities::FinalizeInvoice.call(invoice: first)
    frozen = first.reload.attributes.slice("number", "issued_at", "discount_cents", "total_cents", "coupon_cycle_number")
    Billing::Activities::FinalizeInvoice.call(invoice: first)
    expect(first.reload.attributes.slice(*frozen.keys)).to eq(frozen)
    expect(first.total_cents).to eq(0)
    expect(redemption.reload.cycles_used).to eq(1)
    second = invoice("second-cycle")
    Billing::Activities::FinalizeInvoice.call(invoice: second)
    expect(second.reload.coupon_cycle_number).to eq(2)
    third = invoice("third-cycle")
    Billing::Activities::FinalizeInvoice.call(invoice: third)
    expect(third.reload.discount_cents).to eq(0)
    expect(redemption.reload.cycles_used).to eq(2)
  end

  it "retains an accepted discount after archive and does not replenish cycles on void" do
    coupon = create(:billing_coupon, percent_off: 25, duration: "once")
    Billing::Activities::ApplyCoupon.call(subscription: subscription, coupon: coupon)
    Billing::Catalog::ArchiveCoupon.call(coupon: coupon)
    first = invoice("accepted")
    Billing::Activities::FinalizeInvoice.call(invoice: first)
    expect(first.reload.discount_cents).to eq(2475)
    Billing::Activities::VoidInvoice.call(invoice: first)
    later = invoice("later")
    Billing::Activities::FinalizeInvoice.call(invoice: later)
    expect(later.reload.discount_cents).to eq(0)
    expect(coupon.reload.times_redeemed).to eq(1)
  end
end
