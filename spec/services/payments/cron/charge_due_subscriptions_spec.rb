# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Cron::ChargeDueSubscriptions do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:payment_module) { enable_module!("payment", customer, name: "Payments") }
  let(:user)     { create(:user, customer: customer) }

  before do
    Current.customer = customer
    %w[alipay stripe].each do |provider|
      create(:payment_merchant_account, customer: customer, provider: provider)
    end
  end

  def create_subscription(external_ref:, status: "active", next_charge_at: 1.hour.ago)
    create(:payment_subscription, customer: customer, provider: "alipay",
           external_ref: external_ref, plan_name: "gold",
           amount: 10.00, cycle: "monthly",
           status: status, next_charge_at: next_charge_at)
  end

  it "charges due subscriptions, records the payment succeeded, and advances next_charge_at" do
    sub = create_subscription(external_ref: "due-1")
    original_time = sub.next_charge_at

    expect(Payments::Gateway).to receive(:charge_subscription).with(
      customer: customer, subscription: instance_of(Payments::Subscription),
      payment: instance_of(Payments::Payment)
    ).and_return(psp_transaction_id: "ali_sub_txn_1", raw: { "code" => "10000" })

    described_class.perform

    expect(sub.reload.next_charge_at).to be > original_time
    payment = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id).sole
    # C3: the agreement charge result is now recorded — payment + order reflect success.
    expect(payment.status).to eq("succeeded")
    expect(payment.psp_transaction_id).to eq("ali_sub_txn_1")
    expect(payment.payment_order.reload.status).to eq("paid")
  end

  it "commits the agreement attempt before outbound HTTP without holding its order transaction" do
    create_subscription(external_ref: "agreement-commit-before-http")
    baseline = ActiveRecord::Base.connection.open_transactions
    allow(Payments::Gateway).to receive(:charge_subscription) do |**kwargs|
      expect(ActiveRecord::Base.connection.open_transactions).to eq(baseline)
      expect(Payments::Payment.find(kwargs[:payment].id).merchant_account_id).to be_present
      raise Payments::Errors::TransportError, "timeout"
    end

    described_class.perform

    expect(Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id).sole.status).to eq("created")
  end

  it "copies the subscription currency onto the created order (not the CNY default)" do
    create(:payment_subscription, customer: customer, provider: "alipay",
           external_ref: "usd-sub", plan_name: "gold",
           amount: 50.00, cycle: "monthly", currency: "usd",
           status: "active", next_charge_at: 1.hour.ago)
    allow(Payments::Gateway).to receive(:charge_subscription)
      .and_return(psp_transaction_id: "t", raw: {})

    described_class.perform

    order = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id).sole.payment_order
    expect(order.currency).to eq("USD")
  end

  it "does not double-charge when the period already has a payment (crash recovery)" do
    sub = create_subscription(external_ref: "recover-1")
    order = create(:payment_order, customer: customer,
                   external_ref: "sub-#{sub.id}-#{sub.next_charge_at.to_date}",
                   amount: 10.00, currency: "CNY", subject: "gold")
    create(:payment, payment_order: order, provider: "alipay", flow: "jsapi",
           out_trade_no: "existing-recover", amount: 10.00, status: "succeeded")

    expect(Payments::Gateway).not_to receive(:charge_subscription)

    described_class.perform

    # Period was already charged; the crash-interrupted advance now completes.
    expect(sub.reload.next_charge_at).to be > Time.zone.now
    expect(order.payments.count).to eq(1)
  end

  it "skips subscriptions that are not due yet" do
    create_subscription(external_ref: "not-due-1", next_charge_at: 1.day.from_now)

    expect(Payments::Gateway).not_to receive(:charge_subscription)

    described_class.perform
  end

  it "does not charge when the Payments module is disabled" do
    create_subscription(external_ref: "due-disabled")
    FeatureModules::CustomerAssignment.find_by!(
      customer: customer, feature_module: payment_module
    ).update!(status: :suspended)

    expect(Payments::Gateway).not_to receive(:charge_subscription)
    described_class.perform
  end

  it "swallows Payments::Errors::ApiError and continues processing other subs" do
    sub_bad  = create_subscription(external_ref: "bad-1")
    sub_good = create_subscription(external_ref: "good-1")

    call_count = 0
    allow(Payments::Gateway).to receive(:charge_subscription) do |**_|
      call_count += 1
      raise Payments::Errors::ApiError.new("boom") if call_count == 1
      { psp_transaction_id: "ali_sub_ok", raw: {} }
    end

    expect { described_class.perform }.not_to raise_error

    expect(call_count).to eq(2)
    # bad sub's next_charge_at was NOT advanced (error raised before advance)
    expect(sub_bad.reload.next_charge_at).to be < Time.zone.now
    # good sub's next_charge_at WAS advanced
    expect(sub_good.reload.next_charge_at).to be > Time.zone.now
  end

  describe "card-recurring subscriptions" do
    let(:payment_method) do
      create(:payment_method,
             customer:              customer,
             user:                  user,
             provider:              "stripe",
             psp_customer_id:       "cus_card_cron",
             psp_payment_method_id: "pm_visa_cron",
             brand:                 "visa",
             last4:                 "4242",
             status:                "active")
    end

    let!(:card_sub) do
      create(:payment_subscription,
             customer:       customer,
             provider:       "stripe",
             external_ref:   "card-cron-1",
             plan_name:      "Card Monthly",
             amount: 30.00,
             cycle:          "monthly",
             status:         "active",
             next_charge_at: 1.hour.ago,
             payment_method: payment_method)
    end

    before do
      allow(Payments::Gateway).to receive(:charge_token).and_return(
        psp_transaction_id: "pi_cron_1", status: :succeeded, raw: {}
      )
      allow(Payments::Gateway).to receive(:charge_subscription)
    end

    it "routes card-recurring through charge_token (off-session) instead of charge_subscription" do
      described_class.perform

      expect(Payments::Gateway).to have_received(:charge_token).with(
        customer:       customer,
        order:          instance_of(Payments::Order),
        payment:        instance_of(Payments::Payment),
        payment_method: payment_method
      )
      expect(Payments::Gateway).not_to have_received(:charge_subscription)
    end

    it "advances next_charge_at after a successful card charge" do
      original_time = card_sub.next_charge_at

      described_class.perform

      expect(card_sub.reload.next_charge_at).to be > original_time
    end

    context "when the card is declined" do
      before do
        allow(Payments::Gateway).to receive(:charge_token).and_return(
          psp_transaction_id: nil, status: :failed, raw: { "error" => "insufficient_funds" }
        )
      end

      it "does NOT advance next_charge_at when the card is declined" do
        original_time = card_sub.next_charge_at

        expect { described_class.perform }.not_to raise_error

        expect(card_sub.reload.next_charge_at).to eq(original_time)
      end
    end

    it "creates a Payment row with flow 'card' and status 'succeeded'" do
      described_class.perform

      payment = Payments::Payment.unscoped_by_tenant.where(
        customer_id: customer.id, provider: "stripe"
      ).last
      expect(payment).to be_present
      expect(payment.flow).to eq("card")
      expect(payment.status).to eq("succeeded")
    end

    context "when the charge requires interactive authentication (C2: SCA)" do
      before do
        allow(Payments::Gateway).to receive(:charge_token).and_return(
          psp_transaction_id: nil, status: :pending, raw: { "status" => "requires_action" }
        )
      end

      it "pauses the subscription and does NOT advance next_charge_at (no free period)" do
        original = card_sub.next_charge_at
        expect { described_class.perform }.not_to raise_error
        expect(card_sub.reload.status).to eq("paused")
        expect(card_sub.next_charge_at).to eq(original)
      end
    end

    context "when the vaulted card is no longer chargeable (BUG5: dead card)" do
      before { payment_method.update!(status: "removed") }

      it "pauses the subscription without hitting the PSP" do
        expect(Payments::Gateway).not_to receive(:charge_token)
        described_class.perform
        expect(card_sub.reload.status).to eq("paused")
      end
    end

    describe "two-tick retry safety (C2, L5)" do
      context "tick 1 raises an explicitly definitive PSP rejection" do
        before do
          error = Payments::Errors::ApiError.new("definitive card rejection", code: "x", payload: {})
          error.define_singleton_method(:definitive?) { true }
          allow(Payments::Gateway).to receive(:charge_token)
            .and_raise(error)
        end

        it "marks the payment failed and does NOT advance next_charge_at" do
          original = card_sub.next_charge_at
          expect { described_class.perform }.not_to raise_error

          expect(card_sub.reload.next_charge_at).to eq(original)
          payment = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id, provider: "stripe").sole
          expect(payment.status).to eq("failed")
        end

        it "tick 2 charges a NEW payment row and advances next_charge_at exactly once" do
          described_class.perform # tick 1: fails
          original = card_sub.reload.next_charge_at

          allow(Payments::Gateway).to receive(:charge_token).and_return(
            psp_transaction_id: "pi_tick2", status: :succeeded, raw: {}
          )
          described_class.perform # tick 2: succeeds

          payments = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id, provider: "stripe")
          expect(payments.count).to eq(2)
          expect(payments.where(status: "succeeded").sole.psp_transaction_id).to eq("pi_tick2")
          expect(card_sub.reload.next_charge_at).to be > original
        end
      end

      context "tick 1 raises TransportError (ambiguous — may have processed at PSP)" do
        before do
          allow(Payments::Gateway).to receive(:charge_token)
            .and_raise(Payments::Errors::TransportError, "timeout")
        end

        it "leaves the payment row created and does NOT advance next_charge_at" do
          original = card_sub.next_charge_at
          expect { described_class.perform }.not_to raise_error

          expect(card_sub.reload.next_charge_at).to eq(original)
          payment = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id, provider: "stripe").sole
          expect(payment.status).to eq("created")
        end

        it "tick 2 reuses the SAME payment row (no new row) and advances on success" do
          described_class.perform # tick 1: stalls

          allow(Payments::Gateway).to receive(:charge_token).and_return(
            psp_transaction_id: "pi_tick2b", status: :succeeded, raw: {}
          )
          expect { described_class.perform }.not_to change(Payments::Payment, :count)

          payment = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id, provider: "stripe").sole
          expect(payment.status).to eq("succeeded")
          expect(payment.psp_transaction_id).to eq("pi_tick2b")
          expect(card_sub.reload.next_charge_at).to be > Time.zone.now
        end
      end
    end

    context "when the order has a pending (SCA) payment" do
      it "neither charges nor advances next_charge_at" do
        order = create(:payment_order, customer: customer,
                       external_ref: "sub-#{card_sub.id}-#{card_sub.next_charge_at.to_date}",
                       amount: 30.00, currency: "CNY", subject: "Card Monthly")
        create(:payment, payment_order: order, provider: "stripe", flow: "card",
               out_trade_no: "existing-pending", amount: 30.00, status: "pending")
        original = card_sub.next_charge_at

        expect(Payments::Gateway).not_to receive(:charge_token)

        described_class.perform

        expect(card_sub.reload.next_charge_at).to eq(original)
      end
    end
  end

  describe "agreement-based (non-card) two-tick retry safety (C2, L5)" do
    it "preserves the original attempt when Query cannot yet determine its outcome" do
      sub = create_subscription(external_ref: "agreement-still-open")
      anchor = sub.next_charge_at
      allow(Payments::Gateway).to receive(:charge_subscription).and_raise(Payments::Errors::TransportError, "timeout")
      described_class.perform
      original = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id).sole
      allow(Payments::Gateway).to receive(:query).and_return(status: :pending, raw: {})

      described_class.perform

      expect(Payments::Gateway).to have_received(:charge_subscription).once
      expect(original.reload.status).to eq("created")
      expect(Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id).sole.id).to eq(original.id)
      expect(sub.reload.next_charge_at).to eq(anchor)
    end

    it "does not retire an uncertain agreement attempt on a generic Query API error" do
      sub = create_subscription(external_ref: "agreement-query-error")
      allow(Payments::Gateway).to receive(:charge_subscription).and_raise(Payments::Errors::TransportError, "timeout")
      described_class.perform
      original = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id).sole
      allow(Payments::Gateway).to receive(:query).and_raise(Payments::Errors::ApiError.new("temporary query failure"))

      described_class.perform

      expect(Payments::Gateway).to have_received(:charge_subscription).once
      expect(original.reload.status).to eq("created")
      expect(sub.reload.next_charge_at).to be < Time.current
    end

    it "preserves cancellation when a stale recurring charge enters dunning" do
      sub = create_subscription(external_ref: "cancel-during-dunning")
      allow(Payments::Gateway).to receive(:charge_subscription) do |**kwargs|
        Payments::Subscription.find(kwargs[:subscription].id).mark_cancelled!
        { status: :failed, raw: {} }
      end

      described_class.perform

      expect(sub.reload.status).to eq("cancelled")
      expect(sub.next_charge_at).to be < Time.current
    end

    it "does not schedule invoice-collection mandates owned by Billing" do
      sub = create(:payment_subscription, customer: customer, provider: "alipay", managed_by: "billing",
                   external_ref: "billing-owned", status: "active", next_charge_at: nil)
      expect(Payments::Gateway).not_to receive(:charge_subscription)

      described_class.perform

      expect(sub.reload.charge_claimed_at).to be_nil
      expect(Payments::Order.unscoped_by_tenant.where(customer_id: customer.id)).to be_empty
    end

    it "refuses a stale scheduler claim after ownership changes to Billing" do
      stale = create_subscription(external_ref: "claim-owner-changed")
      Payments::Subscription.find(stale.id).update!(managed_by: "billing", next_charge_at: nil)

      expect(described_class.claim!(stale)).to be(false)
      expect(stale.reload.charge_claimed_at).to be_nil
      expect(Payments::Subscription.due_now).not_to include(stale)
    end

    it "TransportError on tick 1 leaves the payment created; tick 2 resolves via Query without re-submitting" do
      sub = create_subscription(external_ref: "agreement-retry-1")

      allow(Payments::Gateway).to receive(:charge_subscription)
        .and_raise(Payments::Errors::TransportError, "timeout")
      expect { described_class.perform }.not_to raise_error

      payment = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id, provider: "alipay").sole
      expect(payment.status).to eq("created")
      expect(sub.reload.next_charge_at).to be < Time.zone.now

      allow(Payments::Gateway).to receive(:query)
        .and_return(status: :succeeded, psp_transaction_id: "ali_query_resolved", raw: {})

      described_class.perform # tick 2

      expect(Payments::Gateway).to have_received(:charge_subscription).once
      payment.reload
      expect(payment.status).to eq("succeeded")
      expect(payment.psp_transaction_id).to eq("ali_query_resolved")
      expect(Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id, provider: "alipay").count).to eq(1)
      expect(sub.reload.next_charge_at).to be > Time.zone.now
    end
  end

  describe "midnight rollover must not double-charge a stalled payment (H-critical)" do
    it "keys the period order on the billing anchor (next_charge_at), not wall-clock date, so a stalled attempt from before midnight is recovered via Query on the next tick instead of re-charged" do
      sub = nil

      travel_to Time.utc(2026, 7, 13, 23, 5, 0) do
        sub = create_subscription(external_ref: "midnight-1")

        allow(Payments::Gateway).to receive(:charge_subscription)
          .and_raise(Payments::Errors::TransportError, "timeout")

        expect { described_class.perform }.not_to raise_error

        payment = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id, provider: "alipay").sole
        expect(payment.status).to eq("created")
      end

      travel_to Time.utc(2026, 7, 14, 0, 5, 0) do
        allow(Payments::Gateway).to receive(:query)
          .and_return(status: :succeeded, psp_transaction_id: "ali_query_midnight", raw: {})

        described_class.perform

        # Only the tick-1 attempt should have hit charge_subscription; tick 2 must
        # resolve the stalled row via Query, not mint a fresh charge/order.
        expect(Payments::Gateway).to have_received(:charge_subscription).once
        payment = Payments::Payment.unscoped_by_tenant.where(customer_id: customer.id, provider: "alipay").sole
        expect(payment.status).to eq("succeeded")
        expect(payment.psp_transaction_id).to eq("ali_query_midnight")
        expect(Payments::Order.unscoped_by_tenant.where(customer_id: customer.id).count).to eq(1)
        expect(sub.reload.next_charge_at).to be > Time.zone.now
      end
    end
  end

  describe "atomic per-subscription claim (L6)" do
    it "does not clear a newer worker's claim when this worker finishes" do
      sub = create_subscription(external_ref: "claim-reassigned")
      newer_claim = 1.hour.from_now.change(usec: 0)
      allow(Payments::Gateway).to receive(:charge_subscription) do |**kwargs|
        Payments::Subscription.find(kwargs[:subscription].id).update_columns(charge_claimed_at: newer_claim)
        { psp_transaction_id: "captured", raw: {} }
      end

      described_class.perform

      expect(sub.reload.charge_claimed_at).to eq(newer_claim)
    end

    it "skips a subscription claimed by another (still live) worker" do
      sub = create_subscription(external_ref: "claimed-live-1")
      sub.update_columns(charge_claimed_at: 1.minute.ago)

      expect(Payments::Gateway).not_to receive(:charge_subscription)

      described_class.perform

      expect(sub.reload.next_charge_at).to be < Time.zone.now
    end

    it "processes a subscription whose claim is older than CLAIM_TTL (dead worker)" do
      sub = create_subscription(external_ref: "claimed-stale-1")
      sub.update_columns(charge_claimed_at: (described_class::CLAIM_TTL + 1.minute).ago)

      allow(Payments::Gateway).to receive(:charge_subscription)
        .and_return(psp_transaction_id: "t", raw: {})

      described_class.perform

      expect(sub.reload.next_charge_at).to be > Time.zone.now
    end

    it "clears charge_claimed_at after a successful run" do
      sub = create_subscription(external_ref: "claim-clears-1")
      allow(Payments::Gateway).to receive(:charge_subscription)
        .and_return(psp_transaction_id: "t", raw: {})

      described_class.perform

      expect(sub.reload.charge_claimed_at).to be_nil
    end

    it "clears charge_claimed_at even when the charge raises" do
      sub = create_subscription(external_ref: "claim-clears-error-1")
      allow(Payments::Gateway).to receive(:charge_subscription)
        .and_raise(Payments::Errors::ApiError.new("boom", code: "x", payload: {}))

      described_class.perform

      expect(sub.reload.charge_claimed_at).to be_nil
    end
  end

  describe "ensure_order_for uses Time.zone.today (not Date.today)" do
    it "anchors the period order external_ref to the zone-local date, not the system-local date" do
      travel_to Time.utc(2026, 7, 13, 23, 30, 0) do # 23:30 UTC — Date.today is Jul 13
        Time.use_zone("Asia/Shanghai") do # UTC+8 — Time.zone.today is Jul 14
          sub = create_subscription(external_ref: "tz-sub-1")
          expected_ref   = "sub-#{sub.id}-#{Time.zone.today}"
          unexpected_ref = "sub-#{sub.id}-#{Date.today}"
          expect(expected_ref).not_to eq(unexpected_ref)

          allow(Payments::Gateway).to receive(:charge_subscription)
            .and_return(psp_transaction_id: "t", raw: {})

          described_class.perform

          order = Payments::Order.unscoped_by_tenant.find_by(customer_id: customer.id, external_ref: expected_ref)
          expect(order).to be_present
        end
      end
    end
  end
end
