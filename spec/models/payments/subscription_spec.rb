# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Subscription, type: :model do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  # Pure keyword-splat helper — callers pass keywords, so no bare-hash pitfall.
  def create_sub(**attrs)
    described_class.create!(
      { provider: "alipay", plan_name: "p", amount: 1.00 }.merge(attrs)
    )
  end

  it "validates provider, cycle, status" do
    s = described_class.new(provider: "visa", cycle: "hourly", status: "x",
                            external_ref: "r", plan_name: "p", amount: 1.00)
    expect(s).not_to be_valid
    expect(s.errors[:provider]).to be_present
    expect(s.errors[:cycle]).to be_present
    expect(s.errors[:status]).to be_present
  end

  it "enforces unique external_ref per customer" do
    create_sub(cycle: "monthly", external_ref: "r1")
    dup = described_class.new(provider: "alipay", cycle: "monthly",
                              external_ref: "r1", plan_name: "p", amount: 1.00)
    expect(dup).not_to be_valid
  end

  it "mark_active! sets next_charge_at one cycle out" do
    s = create_sub(cycle: "monthly", external_ref: "r2")
    t = Time.zone.parse("2026-04-01T00:00:00Z")
    s.mark_active!(psp_agreement_id: "A", at: t)
    expect(s.reload.next_charge_at).to be_within(1.second).of(t + 1.month)
  end

  it "activates a Billing mandate without putting it on the general recurring schedule" do
    mandate = create(:payment_subscription, customer: customer, managed_by: "billing",
                     status: "pending_sign", next_charge_at: nil)

    mandate.mark_active!(psp_agreement_id: "billing-agreement", at: Time.current)

    expect(mandate.reload.status).to eq("active")
    expect(mandate.next_charge_at).to be_nil
    expect(described_class.due_now).not_to include(mandate)
  end

  it "never schedules or recovers a paused Billing mandate through general subscription transitions" do
    mandate = create(:payment_subscription, customer: customer, managed_by: "billing",
                     status: "paused", next_charge_at: nil)

    mandate.reactivate_paused!
    mandate.advance_next_charge!

    expect(mandate.reload.status).to eq("paused")
    expect(mandate.next_charge_at).to be_nil
  end

  it "mark_cancelled! sets status" do
    s = create_sub(cycle: "daily", external_ref: "r3")
    s.mark_cancelled!
    expect(s.reload.status).to eq("cancelled")
  end

  it ".due_now returns active subs with next_charge_at in the past" do
    past = create_sub(cycle: "daily", external_ref: "past", status: "active",
                      next_charge_at: 1.minute.ago)
    future = create_sub(cycle: "daily", external_ref: "future", status: "active",
                        next_charge_at: 1.hour.from_now)
    expect(described_class.due_now).to include(past)
    expect(described_class.due_now).not_to include(future)
  end

  it "belongs to an optional payment_method" do
    sub = described_class.new
    expect(sub).to respond_to(:payment_method)
  end

  it "is card-recurring when a payment_method is linked" do
    sub = described_class.new(payment_method_id: 1)
    expect(sub.card_recurring?).to be(true)
  end

  it "is not card-recurring when no payment_method is linked" do
    sub = described_class.new
    expect(sub.card_recurring?).to be(false)
  end

  it "has a currency column defaulting to cny" do
    s = create_sub(cycle: "daily", external_ref: "r4")
    expect(s.reload.currency).to eq("cny")
  end

  it "rejects a blank currency instead of relying on the database default after explicit assignment" do
    subscription = build(:payment_subscription, customer: customer, currency: "")

    expect(subscription).not_to be_valid
    expect(subscription.errors[:currency]).to be_present
  end

  it "rounds zero-decimal currency amounts to whole units" do
    subscription = described_class.new(
      provider: "stripe", cycle: "monthly", external_ref: "jpy-fraction",
      plan_name: "p", amount: "1000.50", currency: "jpy"
    )

    expect(subscription).to be_valid
    expect(subscription.amount).to eq(1001.00)
  end

  describe "next_charge_time_from — all cycle branches" do
    let(:t) { Time.zone.parse("2026-06-01T00:00:00Z") }

    it "advances by 1 week for weekly cycle" do
      s = create_sub(cycle: "weekly", external_ref: "w1")
      s.mark_active!(psp_agreement_id: "W", at: t)
      expect(s.reload.next_charge_at).to be_within(1.second).of(t + 1.week)
    end

    it "advances by 1 year for yearly cycle" do
      s = create_sub(cycle: "yearly", external_ref: "y1")
      s.mark_active!(psp_agreement_id: "Y", at: t)
      expect(s.reload.next_charge_at).to be_within(1.second).of(t + 1.year)
    end

    it "advances by 1 day for daily cycle" do
      s = create_sub(cycle: "daily", external_ref: "d1")
      s.mark_active!(psp_agreement_id: "D", at: t)
      expect(s.reload.next_charge_at).to be_within(1.second).of(t + 1.day)
    end
  end

  describe "advance_next_charge!" do
    it "moves next_charge_at forward by one cycle from now" do
      t = Time.zone.parse("2026-05-01T00:00:00Z")
      s = create_sub(cycle: "monthly", external_ref: "adv1", status: "active", next_charge_at: t)
      travel_to(t) do
        s.advance_next_charge!
      end
      expect(s.reload.next_charge_at).to be_within(1.second).of(t + 1.month)
    end

    it "advances from the scheduled anchor, not wall-clock now (BUG4: no drift)" do
      anchor = Time.zone.parse("2026-05-01T00:00:00Z")
      # Cron runs 6 hours late relative to the scheduled charge time.
      run_at = anchor + 6.hours
      s = create_sub(cycle: "monthly", external_ref: "adv2", status: "active", next_charge_at: anchor)
      travel_to(run_at) do
        s.advance_next_charge!
      end
      # Next charge is one month after the ANCHOR, not one month after run_at,
      # so the billing date does not creep later every cycle.
      expect(s.reload.next_charge_at).to be_within(1.second).of(anchor + 1.month)
    end
  end

  describe "mark_paused! (dunning)" do
    %w[cancelled expired].each do |terminal|
      it "preserves persisted #{terminal} against stale dunning, signing and SCA recovery" do
        stale = create_sub(cycle: "monthly", external_ref: "stale-#{terminal}", status: "active",
                           next_charge_at: 1.hour.ago)
        anchor = stale.next_charge_at
        described_class.find(stale.id).update!(status: terminal)

        stale.mark_paused!
        stale.mark_active!(psp_agreement_id: "late-agreement", at: Time.current)
        stale.reactivate_paused!
        stale.advance_next_charge!(expected_anchor: anchor)

        expect(stale.reload.status).to eq(terminal)
        expect(stale.next_charge_at).to eq(anchor)
      end
    end

    it "does not advance or pause a newer anchor from a stale recurring worker" do
      stale = create_sub(cycle: "monthly", external_ref: "stale-anchor", status: "active",
                         next_charge_at: 1.hour.ago)
      original = stale.next_charge_at
      fresh = described_class.find(stale.id)
      fresh.advance_next_charge!(expected_anchor: original)
      next_period = fresh.next_charge_at

      stale.advance_next_charge!(expected_anchor: original)
      stale.mark_paused!(expected_anchor: original)

      expect(stale.reload.status).to eq("active")
      expect(stale.next_charge_at).to eq(next_period)
    end

    it "does not resurrect cancellation committed after an SCA recovery lookup" do
      stale = create_sub(cycle: "monthly", external_ref: "stale-sca", status: "paused",
                         next_charge_at: 1.hour.ago)
      described_class.find(stale.id).mark_cancelled!

      stale.reactivate_paused!

      expect(stale.reload.status).to eq("cancelled")
    end

    it "pauses an active subscription so it is no longer due_now" do
      s = create_sub(cycle: "monthly", external_ref: "pz1", status: "active", next_charge_at: 1.hour.ago)
      expect(described_class.due_now).to include(s)
      s.mark_paused!
      expect(s.reload.status).to eq("paused")
      expect(described_class.due_now).not_to include(s)
    end
  end
end
