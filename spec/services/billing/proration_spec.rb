# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Proration do
  let_it_be(:customer) { create(:customer) }
  # Subscription carries a currency snapshot; defaults to "USD".
  let(:subscription) do
    create(:billing_subscription,
           customer:             customer,
           plan:                 old_plan,
           amount_cents:         old_plan.price_cents_for("USD"),
           currency:             "USD",
           interval:             old_plan.interval,
           current_period_start: period_start,
           current_period_end:   period_end)
  end
  # Plans use dual-currency columns. USD price used throughout these tests.
  let(:old_plan) { create(:billing_plan, name: "Basic", amount_usd: 100.00, amount_cny: 699.00, interval: "monthly") }
  let(:new_plan) { create(:billing_plan, name: "Pro",   amount_usd: 200.00, amount_cny: 1398.00, interval: "monthly") }

  # A subscription that started exactly 1 month ago
  let(:period_start) { Time.zone.parse("2026-06-01 00:00:00") }
  let(:period_end)   { Time.zone.parse("2026-07-01 00:00:00") }

  before { Current.customer = customer }

  # Prorate the subscription onto new_plan at the given instant.
  def prorate(at)
    described_class.credit_and_charge(subscription: subscription, new_plan: new_plan, at: at)
  end

  describe ".credit_and_charge" do
    context "mid-cycle change (exactly halfway through)" do
      # June 1 → July 1 = 30 days; halfway = June 16 (15/30 = 0.5 fraction remaining)
      let(:at) { Time.zone.parse("2026-06-16 00:00:00") }

      it "returns two proration line-item hashes" do
        expect(prorate(at).size).to eq(2)
      end

      it "first item is a negative credit for old plan" do
        credit = prorate(at).first
        expect(credit[:kind]).to eq("proration")
        expect(credit[:amount_cents]).to be < 0
        expect(credit[:description]).to eq("Unused time on Basic")
      end

      it "second item is a positive charge for new plan" do
        charge = prorate(at).last
        expect(charge[:kind]).to eq("proration")
        expect(charge[:amount_cents]).to be > 0
        expect(charge[:description]).to eq("Remaining time on Pro")
      end

      it "credit and charge use the same fraction and the subscription's currency" do
        total_secs = (period_end - period_start).to_f
        remaining  = (period_end - at).to_f
        fraction   = remaining / total_secs
        currency   = subscription.currency  # "USD"

        items = prorate(at)
        expected_credit = -(fraction * old_plan.price_cents_for(currency)).floor
        expected_charge =  (fraction * new_plan.price_cents_for(currency)).floor

        expect(items.first[:amount_cents]).to eq(expected_credit)
        expect(items.last[:amount_cents]).to eq(expected_charge)
      end
    end

    context "change at the very start of the period (full fraction remaining)" do
      let(:at) { period_start }

      it "credits the full old plan amount (negative) in subscription currency" do
        expect(prorate(at).first[:amount_cents]).to eq(-old_plan.price_cents_for(subscription.currency))
      end

      it "charges the full new plan amount in subscription currency" do
        expect(prorate(at).last[:amount_cents]).to eq(new_plan.price_cents_for(subscription.currency))
      end
    end

    context "change at the very end of the period (zero fraction remaining)" do
      let(:at) { period_end }

      it "credits zero (no unused time)" do
        expect(prorate(at).first[:amount_cents]).to eq(0)
      end

      it "charges zero" do
        expect(prorate(at).last[:amount_cents]).to eq(0)
      end
    end

    context "degenerate zero-length period" do
      let(:subscription) do
        create(:billing_subscription,
               customer:             customer,
               plan:                 old_plan,
               amount_cents:         old_plan.price_cents_for("USD"),
               currency:             "USD",
               interval:             old_plan.interval,
               current_period_start: period_start,
               current_period_end:   period_start)  # same start and end
      end

      it "returns zero amounts safely without dividing by zero" do
        items = prorate(period_start)
        expect(items.first[:amount_cents]).to eq(0)
        expect(items.last[:amount_cents]).to eq(0)
      end
    end

    it "includes all required hash keys on each line item" do
      items = prorate(period_start + 15.days)
      items.each do |item|
        expect(item).to include(:description, :amount_cents, :unit_amount_cents, :quantity, :kind)
        expect(item[:kind]).to eq("proration")
        expect(item[:quantity]).to eq(1)
      end
    end
  end
end
