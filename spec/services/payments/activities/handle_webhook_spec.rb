require "rails_helper"

RSpec.describe Payments::Activities::HandleWebhook do
  let_it_be(:customer) { create(:customer) }
  let(:wechat_order) { create(:payment_order, external_ref: "wo", amount: 1.00, subject: "s") }
  let(:wechat_payment) do
    create(:payment, payment_order: wechat_order, provider: "wechat_pay", flow: "qr",
                    out_trade_no: "WX-OT-1", amount: 1.00, status: "pending")
  end
  let(:alipay_order) { create(:payment_order, external_ref: "ao", amount: 2.00, subject: "s") }
  let(:alipay_payment) do
    create(:payment, payment_order: alipay_order, provider: "alipay", flow: "qr",
                    out_trade_no: "AL-OT-1", amount: 2.00, status: "pending")
  end

  before { Current.customer = customer }

  # Stand in for the verifier: every dispatch has an explicit verified account.
  # Merchant-id attack examples keep supplying their own claimed signing identity.
  def dispatch(provider:, verified_payload:, **identity)
    if identity.empty? && %w[wechat_pay alipay stripe paypal].include?(provider)
      account = Payments::MerchantAccount.unscoped_by_tenant.find_by(
        customer_id: Current.customer.id, provider: provider, mode: "sandbox"
      ) || create(:payment_merchant_account, customer: Current.customer, provider: provider)
      identity = { signing_account_id: account.id }
    end
    described_class.call(provider: provider, verified_payload: verified_payload, **identity)
  end

  it "marks WeChat payment succeeded on an explicit SUCCESS trade_state" do
    wechat_payment # materialize
    payload = {
      "out_trade_no" => "WX-OT-1",
      "transaction_id" => "TXN-W1",
      "trade_state" => "SUCCESS"
    }

    dispatch(provider: "wechat_pay", verified_payload: payload)

    expect(wechat_payment.reload.status).to eq("succeeded")
    expect(wechat_payment.psp_transaction_id).to eq("TXN-W1")
    expect(wechat_order.reload.status).to eq("paid")
  end

  it "does NOT mark WeChat succeeded when trade_state is absent (H4: no implicit success)" do
    wechat_payment
    payload = { "out_trade_no" => "WX-OT-1", "transaction_id" => "TXN-W1" }

    dispatch(provider: "wechat_pay", verified_payload: payload)

    expect(wechat_payment.reload.status).to eq("pending")
    expect(wechat_order.reload.status).to eq("pending")
  end

    it "marks Alipay payment succeeded on TRADE_SUCCESS" do
      alipay_payment # materialize
      payload = {
        "out_trade_no" => "AL-OT-1",
        "trade_no"     => "TXN-A1",
        "trade_status" => "TRADE_SUCCESS"
      }

      dispatch(provider: "alipay", verified_payload: payload)

      expect(alipay_payment.reload.status).to eq("succeeded")
      expect(alipay_payment.psp_transaction_id).to eq("TXN-A1")
      expect(alipay_order.reload.status).to eq("paid")
    end

    it "marks a pending Alipay payment closed on TRADE_CLOSED" do
      alipay_payment
      dispatch(
        provider: "alipay",
        verified_payload: { "out_trade_no" => "AL-OT-1", "trade_status" => "TRADE_CLOSED" }
      )

      expect(alipay_payment.reload.status).to eq("closed")
    end

    it "does not close an already succeeded Alipay payment on TRADE_CLOSED" do
      alipay_payment.update!(status: "succeeded")
      dispatch(
        provider: "alipay",
        verified_payload: { "out_trade_no" => "AL-OT-1", "trade_status" => "TRADE_CLOSED" }
      )

      expect(alipay_payment.reload.status).to eq("succeeded")
    end

  it "keeps an unbound billing-inv projection retryable after capture commits" do
    platform = ensure_platform_customer
    tenant = create(:customer)
    invoice = create(:billing_invoice, :open, customer: tenant, total_cents: 200)
    order = create(:payment_order, customer: platform,
                   external_ref: "billing-inv-#{invoice.id}", amount: 2.00, subject: "s")
    payment = create(:payment, customer: platform, payment_order: order, provider: "alipay",
                     flow: "jsapi", out_trade_no: "AL-BILL-1", amount: 2.00, status: "pending")

    Current.customer = platform
    expect { dispatch(
      provider: "alipay",
      verified_payload: {
        "out_trade_no" => "AL-BILL-1",
        "trade_no"     => "TXN-BILL-1",
        "trade_status" => "TRADE_SUCCESS"
      }
    ) }.to raise_error(Payments::Errors::TransportError)

    expect(payment.reload.status).to eq("succeeded")
    expect(invoice.reload.status).to eq("open")
    expect(invoice.payment_id).to be_nil
  end

  it "does not settle a billing invoice from a tenant-owned billing-inv order" do
    tenant = create(:customer)
    invoice = create(:billing_invoice, :open, customer: tenant, total_cents: 200)
    order = create(:payment_order, customer: tenant,
                   external_ref: "billing-inv-#{invoice.id}", amount: 2.00, subject: "s")
    payment = create(:payment, customer: tenant, payment_order: order, provider: "alipay",
                     flow: "jsapi", out_trade_no: "AL-FAKE-1", amount: 2.00, status: "pending")

    Current.customer = tenant
    dispatch(
      provider: "alipay",
      verified_payload: {
        "out_trade_no" => "AL-FAKE-1",
        "trade_no"     => "TXN-FAKE-1",
        "trade_status" => "TRADE_SUCCESS"
      }
    )

    expect(payment.reload.status).to eq("succeeded")
    expect(invoice.reload.status).to eq("open")
    expect(invoice.payment_id).to be_nil
  end

  describe "async refund settlement (H1)" do
    let(:paid_payment) do
      create(:payment, payment_order: wechat_order, provider: "wechat_pay", flow: "qr",
                                out_trade_no: "WX-RF-P", amount: 1.00, status: "succeeded")
    end

    it "settles a WeChat REFUND.SUCCESS by out_refund_no and refunds the order" do
      refund = create(:payment_refund, payment: paid_payment, out_refund_no: "RF-1",
                                        amount: 1.00, status: "processing")
      payload = { "event_type" => "REFUND.SUCCESS",
                  "resource" => { "out_refund_no" => "RF-1", "refund_id" => "wx_re_1",
                                  "refund_status" => "SUCCESS" } }

      dispatch(provider: "wechat_pay", verified_payload: payload)

      expect(refund.reload.status).to eq("succeeded")
      expect(refund.psp_refund_id).to eq("wx_re_1")
      expect(wechat_order.reload.status).to eq("refunded")
    end

    it "marks a WeChat refund failed on REFUND.ABNORMAL" do
      refund = create(:payment_refund, payment: paid_payment, out_refund_no: "RF-2",
                                        amount: 1.00, status: "processing")
      payload = { "event_type" => "REFUND.ABNORMAL",
                  "resource" => { "out_refund_no" => "RF-2", "refund_status" => "ABNORMAL" } }

      dispatch(provider: "wechat_pay", verified_payload: payload)

      expect(refund.reload.status).to eq("failed")
    end

    it "settles a Stripe refund.updated by psp_refund_id" do
      paid_payment.update!(provider: "stripe")
      refund = create(:payment_refund, payment: paid_payment, out_refund_no: "RF-3",
                                        amount: 1.00, status: "processing", psp_refund_id: "re_123")
      payload = { "type" => "refund.updated",
                  "data" => { "object" => { "id" => "re_123", "status" => "succeeded" } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(refund.reload.status).to eq("succeeded")
    end

    it "settles a Stripe refund.updated by metadata out_refund_no when psp_refund_id is not yet stored" do
      paid_payment.update!(provider: "stripe")
      refund = create(:payment_refund, payment: paid_payment, out_refund_no: "RF-3b",
                                        amount: 1.00, status: "processing")
      payload = { "type" => "refund.updated",
                  "data" => { "object" => { "id" => "re_race", "status" => "succeeded",
                                            "metadata" => { "out_refund_no" => "RF-3b" } } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(refund.reload.status).to eq("succeeded")
      expect(refund.psp_refund_id).to eq("re_race")
    end

    it "settles a PayPal PAYMENT.CAPTURE.REFUNDED by psp_refund_id" do
      paid_payment.update!(provider: "paypal")
      refund = create(:payment_refund, payment: paid_payment, out_refund_no: "RF-4",
                                        amount: 1.00, status: "processing", psp_refund_id: "pp_ref_1")
      payload = { "event_type" => "PAYMENT.CAPTURE.REFUNDED",
                  "resource" => { "id" => "pp_ref_1" } }

      dispatch(provider: "paypal", verified_payload: payload)

      expect(refund.reload.status).to eq("succeeded")
    end

    it "settles a PayPal PAYMENT.CAPTURE.REFUNDED by invoice_id when psp_refund_id is not yet stored" do
      paid_payment.update!(provider: "paypal")
      refund = create(:payment_refund, payment: paid_payment, out_refund_no: "RF-4b",
                                        amount: 1.00, status: "processing")
      payload = { "event_type" => "PAYMENT.CAPTURE.REFUNDED",
                  "resource" => { "id" => "pp_race", "invoice_id" => "RF-4b" } }

      dispatch(provider: "paypal", verified_payload: payload)

      expect(refund.reload.status).to eq("succeeded")
      expect(refund.psp_refund_id).to eq("pp_race")
    end

    it "stamps a WeChat refund's succeeded_at from resource.success_time, not local time (D)" do
      refund = create(:payment_refund, payment: paid_payment, out_refund_no: "RF-5",
                                        amount: 1.00, status: "processing")
      payload = { "event_type" => "REFUND.SUCCESS",
                  "resource" => { "out_refund_no" => "RF-5", "refund_id" => "wx_re_5",
                                  "refund_status" => "SUCCESS",
                                  "success_time" => "2026-07-12T23:50:00+08:00" } }

      dispatch(provider: "wechat_pay", verified_payload: payload)

      expect(refund.reload.succeeded_at.to_date).to eq(Date.new(2026, 7, 12))
    end

    it "stamps a Stripe refund's succeeded_at from the Refund object's created, not local time (D)" do
      paid_payment.update!(provider: "stripe")
      refund = create(:payment_refund, payment: paid_payment, out_refund_no: "RF-6",
                                        amount: 1.00, status: "processing", psp_refund_id: "re_456")
      created_at = Time.utc(2026, 7, 10, 8, 0, 0)
      payload = { "type" => "refund.updated",
                  "data" => { "object" => { "id" => "re_456", "status" => "succeeded",
                                            "created" => created_at.to_i } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(refund.reload.succeeded_at).to be_within(1.second).of(created_at)
    end
  end

  describe "SCA-recovery: reactivating a paused subscription (WS6)" do
    let(:sub) do
      create(:payment_subscription, customer: customer, provider: "stripe",
        external_ref: "sca-sub", plan_name: "gold", amount: 30.00, currency: "usd",
        cycle: "monthly", status: "paused", next_charge_at: 2.days.ago)
    end
    let(:sub_order) do
      create(:payment_order, external_ref: "sub-#{sub.id}-#{Date.today}", amount: 30.00,
                              subject: "gold", currency: "USD")
    end
    let!(:sub_payment) do
      create(:payment, payment_order: sub_order, provider: "stripe", flow: "card",
                                out_trade_no: "ct-sca-1", amount: 30.00, status: "pending",
                                psp_transaction_id: "pi_sca")
    end

    it "reactivates the paused subscription and advances it when the PI succeeds" do
      payload = { "type" => "payment_intent.succeeded",
                  "data" => { "object" => { "id" => "pi_sca", "amount" => 3000,
                                            "metadata" => { "out_trade_no" => "ct-sca-1" } } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(sub_payment.reload.status).to eq("succeeded")
      expect(sub.reload.status).to eq("active")
      expect(sub.next_charge_at).to be > Time.zone.now
    end

    it "leaves a non-subscription payment's order untouched" do
      plain_order = create(:payment_order, external_ref: "ORD-XYZ", amount: 10.00, subject: "x")
      create(:payment, payment_order: plain_order, provider: "stripe", flow: "card",
                                out_trade_no: "ct-plain", amount: 10.00, status: "pending",
                                psp_transaction_id: "pi_plain")
      payload = { "type" => "payment_intent.succeeded",
                  "data" => { "object" => { "id" => "pi_plain", "amount" => 1000,
                                            "metadata" => { "out_trade_no" => "ct-plain" } } } }

      expect { dispatch(provider: "stripe", verified_payload: payload) }.not_to raise_error
    end

    it "re-anchors next_charge_at one period forward from reactivation time, not the stale pre-pause anchor (A)" do
      sub.update_columns(next_charge_at: 2.months.ago)
      payload = { "type" => "payment_intent.succeeded",
                  "data" => { "object" => { "id" => "pi_sca", "amount" => 3000,
                                            "metadata" => { "out_trade_no" => "ct-sca-1" } } } }

      dispatch(provider: "stripe", verified_payload: payload)

      sub.reload
      expect(sub.status).to eq("active")
      # One month forward from NOW, not from the stale 2-months-ago anchor —
      # so the cron does not immediately fire an unconsented off-session charge.
      expect(sub.next_charge_at).to be_within(1.hour).of(1.month.from_now)
      expect(Payments::Subscription.due_now).not_to include(sub)
    end

    it "reactivates the subscription with a single atomic write (no intermediate active-and-due row) (race guard)" do
      sub.update_columns(next_charge_at: 2.months.ago)
      payload = { "type" => "payment_intent.succeeded",
                  "data" => { "object" => { "id" => "pi_sca", "amount" => 3000,
                                            "metadata" => { "out_trade_no" => "ct-sca-1" } } } }

      # A separate `update!(status: "active", next_charge_at: <stale-based value>)`
      # followed by a second write would commit an externally-visible moment where
      # the sub is "active" AND next_charge_at is still in the past — exactly the
      # row shape ChargeDueSubscriptions' hourly batch selects via `due_now`, which
      # could claim it and fire a duplicate off-session charge. Counting the
      # UPDATE statements against payment_subscriptions pins that only ONE write
      # ever commits for this subscription during reactivation.
      update_statements = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        update_statements << payload[:sql] if payload[:sql].to_s.match?(/\AUPDATE\s+"?payment_subscriptions"?/i)
      end

      begin
        dispatch(provider: "stripe", verified_payload: payload)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(update_statements.size).to eq(1)
      expect(sub.reload.status).to eq("active")
      expect(sub.next_charge_at).to be_within(1.hour).of(1.month.from_now)
    end

    it "does NOT reactivate a paused subscription belonging to a different tenant (M3)" do
      tenant_b = create(:customer)
      b_sub = create(:payment_subscription, customer: tenant_b, provider: "stripe",
        external_ref: "sca-sub-b", plan_name: "gold", amount: 30.00, currency: "usd",
        cycle: "monthly", status: "paused", next_charge_at: 2.days.ago)
      original_next_charge_at = b_sub.next_charge_at

      # A payment for tenant A (the outer `customer`) whose order external_ref
      # happens to encode tenant B's subscription id.
      cross_order = create(:payment_order, customer: customer, external_ref: "sub-#{b_sub.id}-x",
                                            amount: 30.00, subject: "gold")
      cross_payment = create(:payment, customer: customer, payment_order: cross_order, provider: "stripe", flow: "card",
                                out_trade_no: "ct-cross-1", amount: 30.00, status: "pending",
                                psp_transaction_id: "pi_cross")

      payload = { "type" => "payment_intent.succeeded",
                  "data" => { "object" => { "id" => "pi_cross", "amount" => 3000,
                                            "metadata" => { "out_trade_no" => "ct-cross-1" } } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(cross_payment.reload.status).to eq("succeeded")
      expect(b_sub.reload.status).to eq("paused")
      expect(b_sub.next_charge_at).to be_within(1.second).of(original_next_charge_at)
    end
  end

  describe "Stripe dispute / chargeback recording (L3)" do
    let(:stripe_order) { create(:payment_order, external_ref: "st-d", amount: 5.00, subject: "s") }
    let!(:stripe_payment) do
      create(:payment, payment_order: stripe_order, provider: "stripe", flow: "card",
                                out_trade_no: "ST-D-1", amount: 5.00, status: "succeeded",
                                psp_transaction_id: "pi_disputed")
    end

    def dispute_event(status)
      { "type" => "charge.dispute.created",
        "data" => { "object" => { "id" => "dp_1", "payment_intent" => "pi_disputed",
                                  "reason" => "fraudulent", "status" => status, "amount" => 500 } } }
    end

    it "records a new dispute linked to the payment" do
      dispatch(provider: "stripe", verified_payload: dispute_event("needs_response"))

      dispute = Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "dp_1")
      expect(dispute).to be_present
      expect(dispute.payment_id).to eq(stripe_payment.id)
      expect(dispute.status).to eq("open")
      expect(dispute.reason).to eq("fraudulent")
      expect(dispute.amount).to eq(5.00)
      expect(dispute.opened_at).to be_present
    end

    it "upserts the same dispute row as it progresses to lost (chargeback)" do
      dispatch(provider: "stripe", verified_payload: dispute_event("under_review"))
      dispatch(provider: "stripe", verified_payload: dispute_event("lost"))

      disputes = Payments::Dispute.unscoped_by_tenant.where(psp_dispute_id: "dp_1")
      expect(disputes.count).to eq(1)
      expect(disputes.first.status).to eq("lost")
      expect(disputes.first.resolved_at).to be_present
    end

    it "is a no-op when no local payment matches the disputed payment_intent" do
      event = dispute_event("won").tap { |e| e["data"]["object"]["payment_intent"] = "pi_unknown" }
      expect {
        dispatch(provider: "stripe", verified_payload: event)
      }.not_to change(Payments::Dispute.unscoped_by_tenant, :count)
    end

    describe "resolved status never downgrades (M8)" do
      it "does not reopen a resolved dispute on a delayed non-terminal event" do
        dispatch(provider: "stripe", verified_payload: dispute_event("won"))
        expect(Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "dp_1").status).to eq("won")

        dispatch(provider: "stripe", verified_payload: dispute_event("under_review"))

        expect(Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "dp_1").status).to eq("won")
      end

      it "still advances a non-resolved dispute from open to under_review" do
        dispatch(provider: "stripe", verified_payload: dispute_event("needs_response"))
        expect(Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "dp_1").status).to eq("open")

        dispatch(provider: "stripe", verified_payload: dispute_event("under_review"))

        expect(Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "dp_1").status).to eq("under_review")
      end

      it "still applies a resolved-to-resolved transition (won -> lost)" do
        dispatch(provider: "stripe", verified_payload: dispute_event("won"))
        dispatch(provider: "stripe", verified_payload: dispute_event("lost"))

        expect(Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "dp_1").status).to eq("lost")
      end
    end
  end

  describe "PayPal dispute / chargeback recording (L3)" do
    let(:pp_order) { create(:payment_order, external_ref: "pp-d", amount: 5.00, subject: "s") }
    let!(:pp_payment) do
      create(:payment, payment_order: pp_order, provider: "paypal", flow: "card",
                                out_trade_no: "PP-D-1", amount: 5.00, status: "succeeded",
                                psp_transaction_id: "CAP-123")
    end

    def pp_dispute_event(event_type, status:, outcome: nil)
      { "event_type" => event_type,
        "resource" => {
          "dispute_id" => "PP-DISP-1", "reason" => "MERCHANDISE_OR_SERVICE_NOT_RECEIVED",
          "status" => status, "dispute_outcome" => (outcome && { "outcome_code" => outcome }),
          "dispute_amount" => { "currency_code" => "USD", "value" => "5.00" },
          "disputed_transactions" => [ { "seller_transaction_id" => "CAP-123" } ]
        }.compact }
    end

    it "records a new PayPal dispute linked via the disputed capture id" do
      dispatch(provider: "paypal",
        verified_payload: pp_dispute_event("CUSTOMER.DISPUTE.CREATED", status: "OPEN"))

      dispute = Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "PP-DISP-1")
      expect(dispute).to be_present
      expect(dispute.provider).to eq("paypal")
      expect(dispute.payment_id).to eq(pp_payment.id)
      expect(dispute.status).to eq("open")
      expect(dispute.amount).to eq(5.00)
    end

    it "records a dispute with zero amount when PayPal omits dispute_amount" do
      payload = pp_dispute_event("CUSTOMER.DISPUTE.CREATED", status: "OPEN")
      payload["resource"].delete("dispute_amount")

      expect {
        dispatch(provider: "paypal", verified_payload: payload)
      }.to change(Payments::Dispute.unscoped_by_tenant, :count).by(1)

      expect(
        Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "PP-DISP-1").amount
      ).to eq(0)
    end

    it "maps RESOLVED in the seller's favour to won" do
      dispatch(provider: "paypal",
        verified_payload: pp_dispute_event("CUSTOMER.DISPUTE.RESOLVED", status: "RESOLVED",
                                           outcome: "RESOLVED_SELLER_FAVOUR"))
      expect(Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "PP-DISP-1").status).to eq("won")
    end

    it "maps RESOLVED in the buyer's favour to lost (chargeback)" do
      dispatch(provider: "paypal",
        verified_payload: pp_dispute_event("CUSTOMER.DISPUTE.RESOLVED", status: "RESOLVED",
                                           outcome: "RESOLVED_BUYER_FAVOUR"))
      dispute = Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "PP-DISP-1")
      expect(dispute.status).to eq("lost")
      expect(dispute.resolved_at).to be_present
    end
  end

  it "raises for an unrecognised provider instead of silently no-op'ing a verified event (E)" do
    expect {
      dispatch(provider: "new_gateway", verified_payload: { "out_trade_no" => "X" })
    }.to raise_error(ArgumentError, /new_gateway/)
  end

  it "is a no-op for an unknown out_trade_no" do
    expect {
      dispatch(provider: "wechat_pay",
                           verified_payload: { "out_trade_no" => "GHOST" })
    }.not_to raise_error
  end

  it "leaves Alipay payment pending on non-terminal trade_status" do
    alipay_payment # materialize
    payload = {
      "out_trade_no" => "AL-OT-1",
      "trade_no"     => "TXN-A2",
      "trade_status" => "WAIT_BUYER_PAY"
    }

    dispatch(provider: "alipay", verified_payload: payload)

    expect(alipay_payment.reload.status).to eq("pending")
  end

  it "marks Alipay payment succeeded on TRADE_FINISHED" do
    alipay_payment
    payload = {
      "out_trade_no" => "AL-OT-1",
      "trade_no"     => "TXN-A3",
      "trade_status" => "TRADE_FINISHED"
    }
    dispatch(provider: "alipay", verified_payload: payload)
    expect(alipay_payment.reload.status).to eq("succeeded")
  end

  describe "signing_matches_payment? cross-tenant guard" do
    let(:active_account) do
      create(:payment_merchant_account, :alipay,
        customer: customer,
        provider: "alipay", mode: "sandbox",
        merchant_id: "2088real", status: "active"
      )
    end

    it "rejects missing verification identity rather than trusting the payload's trade reference" do
      alipay_payment
      described_class.call(provider: "alipay", verified_payload: {
        "out_trade_no" => alipay_payment.out_trade_no, "trade_status" => "TRADE_SUCCESS"
      })

      expect(alipay_payment.reload.status).to eq("pending")
    end

    it "rejects a forged Stripe binding to another provider even when merchant IDs coincide" do
      active_account
      alipay_payment
      attacker = create(:customer)
      account = create(:payment_merchant_account, customer: attacker, provider: "stripe",
                       merchant_id: active_account.merchant_id)
      payload = { "type" => "payment_intent.succeeded", "data" => { "object" => {
        "id" => "pi_forged", "amount_received" => 200, "currency" => "cny",
        "metadata" => { "out_trade_no" => alipay_payment.out_trade_no }
      } } }

      described_class.call(provider: "stripe", verified_payload: payload,
                           signing_account_id: account.id, signing_merchant_id: account.merchant_id)

      expect(alipay_payment.reload.status).to eq("pending")
      expect(alipay_order.reload.status).to eq("pending")
    end

    it "does not use a verified account ID from a different incoming provider" do
      active_account
      alipay_payment
      payload = { "out_trade_no" => alipay_payment.out_trade_no, "trade_status" => "TRADE_SUCCESS" }

      foreign_provider = create(:payment_merchant_account, customer: customer, provider: "stripe")
      expect {
        described_class.call(provider: "alipay", verified_payload: payload, signing_account_id: foreign_provider.id)
      }.to raise_error(Payments::Errors::CredentialsMissing)

      expect(alipay_payment.reload.status).to eq("pending")
    end

    it "accepts the exact disabled historical account, independent of the current environment mode" do
      historical = create(:payment_merchant_account, customer: customer, provider: "alipay",
                          mode: "production", status: "disabled")
      alipay_payment.update!(prepay_payload: { "_attempt" => {
        "merchant_account_id" => historical.id, "merchant_id" => historical.merchant_id, "mode" => historical.mode
      } })
      payload = { "out_trade_no" => alipay_payment.out_trade_no, "trade_status" => "TRADE_SUCCESS" }

      described_class.call(provider: "alipay", verified_payload: payload, signing_account_id: historical.id)

      expect(alipay_payment.reload.status).to eq("succeeded")
    end

    it "settles already verified evidence after the account's merchant routing label changes" do
      original = active_account
      old_merchant_id = original.merchant_id
      alipay_payment.update!(prepay_payload: { "_attempt" => {
        "merchant_account_id" => original.id, "merchant_id" => old_merchant_id, "mode" => original.mode
      } })
      original.update!(merchant_id: "merchant-after-receipt", status: "disabled")
      payload = { "out_trade_no" => alipay_payment.out_trade_no, "trade_status" => "TRADE_SUCCESS", "total_amount" => "2.00" }

      described_class.call(provider: "alipay", verified_payload: payload,
                           signing_account_id: original.id, signing_merchant_id: old_merchant_id)

      expect(alipay_payment.reload.status).to eq("succeeded")
    end

    it "rejects the same tenant's other account when an attempt is bound to a specific historical row" do
      original = active_account
      other = create(:payment_merchant_account, customer: customer, provider: "alipay", mode: "production")
      alipay_payment.update!(prepay_payload: { "_attempt" => {
        "merchant_account_id" => original.id, "merchant_id" => original.merchant_id, "mode" => original.mode
      } })
      payload = { "out_trade_no" => alipay_payment.out_trade_no, "trade_status" => "TRADE_SUCCESS" }

      described_class.call(provider: "alipay", verified_payload: payload, signing_account_id: other.id)

      expect(alipay_payment.reload.status).to eq("pending")
    end

    it "rejects Stripe refund metadata and PSP IDs that point to another provider's refund" do
      refund = create(:payment_refund, payment: alipay_payment, amount: 2.00,
                      status: "processing", psp_refund_id: "re_collision")
      signer = create(:payment_merchant_account, customer: customer, provider: "stripe")
      payload = { "type" => "refund.updated", "data" => { "object" => {
        "id" => "re_collision", "status" => "succeeded",
        "metadata" => { "out_refund_no" => refund.out_refund_no }
      } } }

      described_class.call(provider: "stripe", verified_payload: payload, signing_account_id: signer.id)

      expect(refund.reload.status).to eq("processing")
    end

    it "scopes colliding PSP refund IDs to the verified tenant before selecting a row" do
      signer = create(:payment_merchant_account, customer: customer, provider: "stripe")
      other_customer = create(:customer)
      other_payment = create(:payment, customer: other_customer, provider: "stripe", status: "succeeded")
      foreign = create(:payment_refund, customer: other_customer, payment: other_payment,
                       status: "processing", psp_refund_id: "re_shared")
      own_payment = create(:payment, customer: customer, provider: "stripe", status: "succeeded")
      own = create(:payment_refund, payment: own_payment, status: "processing", psp_refund_id: "re_shared")
      payload = { "type" => "refund.updated", "data" => { "object" => {
        "id" => "re_shared", "status" => "succeeded"
      } } }

      described_class.call(provider: "stripe", verified_payload: payload, signing_account_id: signer.id)

      expect(own.reload.status).to eq("succeeded")
      expect(foreign.reload.status).to eq("processing")
    end

    it "passes when signing_merchant_id matches the payment's merchant account" do
      active_account
      alipay_payment
      payload = {
        "out_trade_no" => "AL-OT-1",
        "trade_no"     => "TXN-MATCH",
        "trade_status" => "TRADE_SUCCESS"
      }
      dispatch(provider: "alipay", verified_payload: payload,
                           signing_merchant_id: "2088real")
      expect(alipay_payment.reload.status).to eq("succeeded")
    end

    it "drops the webhook when signing_merchant_id does not match the payment's merchant" do
      active_account
      alipay_payment
      payload = {
        "out_trade_no" => "AL-OT-1",
        "trade_no"     => "TXN-MISMATCH",
        "trade_status" => "TRADE_SUCCESS"
      }
      dispatch(provider: "alipay", verified_payload: payload,
                           signing_merchant_id: "9999wrong")
      expect(alipay_payment.reload.status).to eq("pending")
    end

    it "drops the webhook when no merchant account exists for the payment's customer" do
      # No merchant account created — unscoped_by_tenant finds nothing.
      alipay_payment
      payload = {
        "out_trade_no" => "AL-OT-1",
        "trade_no"     => "TXN-NOACCT",
        "trade_status" => "TRADE_SUCCESS"
      }
      dispatch(provider: "alipay", verified_payload: payload,
                           signing_merchant_id: "2088phantom")
      expect(alipay_payment.reload.status).to eq("pending")
    end

    it "drops a webhook signed by the same tenant's other-mode merchant" do
      active_account
      create(:payment_merchant_account, :alipay,
        customer: customer, provider: "alipay", mode: "production",
        merchant_id: "2088prod", status: "active"
      )
      alipay_payment
      payload = {
        "out_trade_no" => "AL-OT-1",
        "trade_no"     => "TXN-OTHER-MODE",
        "trade_status" => "TRADE_SUCCESS"
      }
      dispatch(provider: "alipay", verified_payload: payload,
                           signing_merchant_id: "2088prod")
      expect(alipay_payment.reload.status).to eq("pending")
    end
  end

  describe "WeChat non-terminal trade_state handling" do
    it "leaves payment pending on PAYERROR" do
      wechat_payment
      payload = { "out_trade_no" => "WX-OT-1", "transaction_id" => "TXN-PE",
                  "trade_state" => "PAYERROR" }
      dispatch(provider: "wechat_pay", verified_payload: payload)
      expect(wechat_payment.reload.status).to eq("pending")
    end

    it "leaves payment pending on USERPAYING" do
      wechat_payment
      payload = { "out_trade_no" => "WX-OT-1", "transaction_id" => "TXN-UP",
                  "trade_state" => "USERPAYING" }
      dispatch(provider: "wechat_pay", verified_payload: payload)
      expect(wechat_payment.reload.status).to eq("pending")
    end

    it "leaves payment pending on NOTPAY" do
      wechat_payment
      payload = { "out_trade_no" => "WX-OT-1", "transaction_id" => "TXN-NP",
                  "trade_state" => "NOTPAY" }
      dispatch(provider: "wechat_pay", verified_payload: payload)
      expect(wechat_payment.reload.status).to eq("pending")
    end

    it "marks closed on a CLOSED trade_state" do
      wechat_payment
      payload = { "out_trade_no" => "WX-OT-1", "trade_state" => "CLOSED" }
      dispatch(provider: "wechat_pay", verified_payload: payload)
      expect(wechat_payment.reload.status).to eq("closed")
    end

    it "does NOT close a payment on a stray REFUND trade_state (refunds are their own event)" do
      wechat_payment
      payload = { "out_trade_no" => "WX-OT-1", "trade_state" => "REFUND" }
      dispatch(provider: "wechat_pay", verified_payload: payload)
      expect(wechat_payment.reload.status).to eq("pending")
    end
  end

  describe "WeChat idempotency guard" do
    it "is a no-op when payment is already in terminal succeeded state" do
      # Force payment into terminal state first
      wechat_payment.update_columns(status: "succeeded")
      payload = { "out_trade_no" => "WX-OT-1", "transaction_id" => "REPLAY-1" }
      dispatch(provider: "wechat_pay", verified_payload: payload)
      # psp_transaction_id unchanged — the replay was dropped
      expect(wechat_payment.reload.psp_transaction_id).to be_nil
    end

    it "recovers a failed payment when a verified SUCCESS arrives" do
      wechat_payment.update_columns(status: "failed")
      payload = { "out_trade_no" => "WX-OT-1", "trade_state" => "SUCCESS", "transaction_id" => "WX-LATE" }
      dispatch(provider: "wechat_pay", verified_payload: payload)
      expect(wechat_payment.reload.status).to eq("succeeded")
      expect(wechat_payment.psp_transaction_id).to eq("WX-LATE")
    end
  end

  describe "stripe setup_intent.succeeded" do
    let(:user) { create(:user, customer: customer) }
    let!(:pending_pm) do
      create(:payment_method,
        customer:              customer,
        user:                  user,
        provider:              "stripe",
        psp_customer_id:       "cus_vault_1",
        psp_payment_method_id: "pending:seti_vault_1",
        status:                "active",
        brand:                 nil,
        last4:                 nil,
        exp_month:             nil,
        exp_year:              nil
      )
    end

    # Realistic setup_intent.succeeded object — note: does NOT carry
    # payment_method_details.card. Card details come from the PaymentMethod
    # resource fetched via GET /v1/payment_methods/:id.
    let(:setup_intent_object) do
      {
        "id"             => "seti_vault_1",
        "customer"       => "cus_vault_1",
        "payment_method" => "pm_visa_4242",
        "status"         => "succeeded"
        # no payment_method_details here — that field is on Charge objects
      }
    end

    before do
      allow(Payments::Gateway).to receive(:fetch_payment_method).and_return(
        brand: "visa", last4: "4242", exp_month: 12, exp_year: 2027
      )
    end

    it "fetches card details via Gateway#fetch_payment_method (not from SetupIntent body)" do
      payload = { "type" => "setup_intent.succeeded", "data" => { "object" => setup_intent_object } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(Payments::Gateway).to have_received(:fetch_payment_method).with(
        customer:  customer,
        provider:  "stripe",
        psp_pm_id: "pm_visa_4242",
        merchant_account: instance_of(Payments::MerchantAccount), historical: true
      )
    end

    it "backfills brand/last4/exp and real psp_payment_method_id on the pending PaymentMethod" do
      payload = { "type" => "setup_intent.succeeded", "data" => { "object" => setup_intent_object } }

      dispatch(provider: "stripe", verified_payload: payload)

      pending_pm.reload
      expect(pending_pm.psp_payment_method_id).to eq("pm_visa_4242")
      expect(pending_pm.brand).to eq("visa")
      expect(pending_pm.last4).to eq("4242")
      expect(pending_pm.exp_month).to eq(12)
      expect(pending_pm.exp_year).to eq(2027)
    end

    it "backfills the pending row bound to this SetupIntent, not an older sibling" do
      older = create(:payment_method,
        customer:              customer,
        user:                  user,
        provider:              "stripe",
        psp_customer_id:       "cus_vault_1",
        psp_payment_method_id: "pending:seti_older",
        status:                "active",
        created_at:            1.hour.ago
      )
      newer = create(:payment_method,
        customer:              customer,
        user:                  user,
        provider:              "stripe",
        psp_customer_id:       "cus_vault_1",
        psp_payment_method_id: "pending:seti_newer",
        status:                "active"
      )
      payload = {
        "type" => "setup_intent.succeeded",
        "data" => { "object" => setup_intent_object.merge("id" => "seti_newer") }
      }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(newer.reload.psp_payment_method_id).to eq("pm_visa_4242")
      expect(older.reload.psp_payment_method_id).to eq("pending:seti_older")
    end

    it "is a no-op when no pending PaymentMethod matches the psp_customer_id" do
      payload = {
        "type" => "setup_intent.succeeded",
        "data" => { "object" => { "customer" => "cus_unknown", "payment_method" => "pm_xyz" } }
      }
      expect { dispatch(provider: "stripe", verified_payload: payload) }
        .not_to raise_error
    end

    context "cross-tenant setup_intent attack" do
      # attacker_customer has a Stripe MerchantAccount with merchant_id "acct_attacker"
      # victim_customer has a pending PaymentMethod they are trying to overwrite
      let(:attacker_customer) { create(:customer) }
      let(:victim_customer)   { create(:customer) }
      let(:victim_user)       { create(:user, customer: victim_customer) }

      let!(:victim_pm) do
        create(:payment_method,
          customer:              victim_customer,
          user:                  victim_user,
          provider:              "stripe",
          psp_customer_id:       "cus_victim_1",
          psp_payment_method_id: "pending:victimtoken",
          status:                "active",
          brand:                 nil,
          last4:                 nil,
          exp_month:             nil,
          exp_year:              nil
        )
      end

      let!(:attacker_merchant) do
        create(:payment_merchant_account, :stripe,
          customer:    attacker_customer,
          provider:    "stripe",
          mode:        "sandbox",
          merchant_id: "acct_attacker",
          status:      "active"
        )
      end

      it "does NOT backfill a PaymentMethod that belongs to a different tenant than the signing merchant" do
        # The SetupIntent webhook is signed by acct_attacker (attacker_customer),
        # but references a psp_customer_id belonging to victim_customer.
        payload = {
          "type" => "setup_intent.succeeded",
          "data" => {
            "object" => {
              "customer"       => "cus_victim_1",
              "id"             => "victimtoken",
              "payment_method" => "pm_stolen"
            }
          }
        }

        dispatch(provider: "stripe", verified_payload: payload,
                             signing_merchant_id: "acct_attacker")

        # The victim's pending PaymentMethod must remain unchanged.
        victim_pm.reload
        expect(victim_pm.psp_payment_method_id).to eq("pending:victimtoken")
        expect(victim_pm.brand).to be_nil
      end
    end
  end

  describe "PayPal PAYMENT.CAPTURE.COMPLETED" do
    let!(:paypal_account) do
      create(:payment_merchant_account, :paypal,
        customer: customer,
        provider: "paypal", mode: "sandbox",
        merchant_id: "PAYPAL-MERCHANT-1", status: "active"
      )
    end

    let(:paypal_order) { create(:payment_order, external_ref: "po", amount: 10.00, subject: "s", currency: "USD") }
    let!(:paypal_payment) do
      create(:payment, payment_order: paypal_order, provider: "paypal", flow: "card",
                                out_trade_no: "PP-OT-1", amount: 10.00, status: "pending")
    end

    let(:capture_payload) do
      {
        "event_type" => "PAYMENT.CAPTURE.COMPLETED",
        "resource"   => {
          "id"            => "CAP-123",
          "status"        => "COMPLETED",
          "invoice_id"    => "PP-OT-1",
          "custom_id"     => "PAYPAL-MERCHANT-1",
          "amount"        => { "value" => "10.00", "currency_code" => "USD" }
        }
      }
    end

    it "marks the payment succeeded and sets psp_transaction_id to the capture id" do
      dispatch(provider: "paypal", verified_payload: capture_payload,
                           signing_merchant_id: "PAYPAL-MERCHANT-1")

      expect(paypal_payment.reload.status).to eq("succeeded")
      expect(paypal_payment.psp_transaction_id).to eq("CAP-123")
      expect(paypal_order.reload.status).to eq("paid")
    end

    it "does not mark paid when the capture currency differs from the order" do
      payload = capture_payload.deep_dup
      payload["resource"]["amount"] = { "value" => "10.00", "currency_code" => "EUR" }

      dispatch(provider: "paypal", verified_payload: payload,
                           signing_merchant_id: "PAYPAL-MERCHANT-1")

      expect(paypal_payment.reload.status).to eq("pending")
      expect(paypal_order.reload.status).to eq("pending")
    end

    describe ".paypal_amount" do
      it "reads the capture-webhook amount.value" do
        expect(described_class.paypal_amount(capture_payload["resource"])).to eq(BigDecimal("10.00"))
      end

      it "reads a nested Order capture amount used by Query" do
        order = {
          "purchase_units" => [{
            "amount" => { "currency_code" => "USD", "value" => "10.00" },
            "payments" => {
              "captures" => [{ "amount" => { "currency_code" => "USD", "value" => "0.01" } }]
            }
          }]
        }
        expect(described_class.paypal_amount(order)).to eq(BigDecimal("0.01"))
      end

      it "does not treat the purchase-unit amount as a capture amount" do
        order = {
          "purchase_units" => [{
            "amount" => { "currency_code" => "USD", "value" => "10.00" },
            "payments" => { "captures" => [{ "id" => "CAP-bare" }] }
          }]
        }
        expect(described_class.paypal_amount(order)).to be_nil
      end
    end

    it "drops the webhook when signing_merchant_id does not match the payment's merchant account" do
      dispatch(provider: "paypal", verified_payload: capture_payload,
                           signing_merchant_id: "PAYPAL-WRONG-MERCHANT")

      expect(paypal_payment.reload.status).to eq("pending")
    end

    describe "idempotency" do
      it "is a no-op when payment is already succeeded" do
        paypal_payment.update_columns(status: "succeeded")
        dispatch(provider: "paypal", verified_payload: capture_payload,
                             signing_merchant_id: "PAYPAL-MERCHANT-1")

        expect(paypal_payment.reload.psp_transaction_id).to be_nil
      end

      %w[failed closed].each do |terminal|
        it "recovers a #{terminal} payment when a verified capture arrives" do
          paypal_payment.update_columns(status: terminal)
          dispatch(provider: "paypal", verified_payload: capture_payload,
                               signing_merchant_id: "PAYPAL-MERCHANT-1")

          expect(paypal_payment.reload.status).to eq("succeeded")
          expect(paypal_payment.psp_transaction_id).to eq("CAP-123")
        end
      end
    end

    it "is a no-op for unrecognised event_type" do
      other_event = capture_payload.merge("event_type" => "PAYMENT.CAPTURE.DENIED")
      dispatch(provider: "paypal", verified_payload: other_event,
                           signing_merchant_id: "PAYPAL-MERCHANT-1")

      expect(paypal_payment.reload.status).to eq("pending")
    end
  end

  describe "stripe payment_intent.succeeded" do
    # Two real tenants, each with their own active MerchantAccount row.
    # This exercises signing_matches_payment? with real DB fixtures — no stubs.
    let(:tenant_a)     { create(:customer) }
    let(:tenant_b)     { create(:customer) }

    let!(:account_a) do
      create(:payment_merchant_account, :stripe,
        customer:    tenant_a,
        provider:    "stripe",
        mode:        "sandbox",
        merchant_id: "acct_tenant_a",
        status:      "active"
      )
    end

    let!(:account_b) do
      create(:payment_merchant_account, :stripe,
        customer:    tenant_b,
        provider:    "stripe",
        mode:        "sandbox",
        merchant_id: "acct_tenant_b",
        status:      "active"
      )
    end

    # Payment that belongs to tenant_a.
    let(:stripe_order) do
      Current.customer = tenant_a
      create(:payment_order, customer: tenant_a, external_ref: "stripe-o1", amount: 10.00, subject: "s")
    end

    let!(:stripe_payment) do
      Current.customer = tenant_a
      create(:payment, customer: tenant_a, payment_order: stripe_order, provider: "stripe", flow: "card",
                                out_trade_no: "STRIPE-OT-1", amount: 10.00, status: "pending")
    end

    let(:pi_succeeded_payload) do
      {
        "type" => "payment_intent.succeeded",
        "data" => {
          "object" => {
            "id"       => "pi_abc",
            "status"   => "succeeded",
            "metadata" => { "out_trade_no" => "STRIPE-OT-1" }
          }
        }
      }
    end

    it "marks the payment succeeded when the signing merchant owns the payment's tenant" do
      dispatch(provider: "stripe", verified_payload: pi_succeeded_payload,
                           signing_merchant_id: "acct_tenant_a")

      expect(stripe_payment.reload.status).to eq("succeeded")
      expect(stripe_payment.psp_transaction_id).to eq("pi_abc")
    end

    it "is a no-op when the signing merchant belongs to a DIFFERENT tenant (real fixture, no stubs)" do
      # tenant_b's merchant signs a body referencing tenant_a's out_trade_no.
      dispatch(provider: "stripe", verified_payload: pi_succeeded_payload,
                           signing_merchant_id: "acct_tenant_b")

      # tenant_a's payment must remain untouched.
      expect(stripe_payment.reload.status).to eq("pending")
    end

    it "is a no-op when no out_trade_no is present in metadata" do
      expect {
        dispatch(provider: "stripe",
                             verified_payload: { "type" => "payment_intent.succeeded",
                                                 "data" => { "object" => { "id" => "pi_x" } } })
      }.not_to raise_error
    end

    it "backfills a checkout save-card placeholder keyed to the PaymentIntent id" do
      member = create(:user, :member, customer: tenant_a)
      create(:payment_method,
             customer: tenant_a, user: member, provider: "stripe",
             psp_customer_id: "cus_checkout",
             psp_payment_method_id: "pending:pi_abc",
             status: "active")
      allow(Payments::Gateway).to receive(:fetch_payment_method).and_return(
        brand: "visa", last4: "4242", exp_month: 12, exp_year: 2028
      )

      payload = {
        "type" => "payment_intent.succeeded",
        "data" => {
          "object" => {
            "id" => "pi_abc",
            "status" => "succeeded",
            "customer" => "cus_checkout",
            "payment_method" => "pm_visa_4242",
            "metadata" => { "out_trade_no" => "STRIPE-OT-1" }
          }
        }
      }
      dispatch(provider: "stripe", verified_payload: payload,
                           signing_merchant_id: "acct_tenant_a")

      pm = Payments::PaymentMethod.find_by!(psp_payment_method_id: "pm_visa_4242")
      expect(pm.last4).to eq("4242")
      expect(pm).to be_chargeable
    end

    it "backfills a save-card placeholder even when Query already marked the payment succeeded" do
      stripe_payment.update_columns(status: "succeeded", psp_transaction_id: "pi_abc")
      member = create(:user, :member, customer: tenant_a)
      create(:payment_method,
             customer: tenant_a, user: member, provider: "stripe",
             psp_customer_id: "cus_late",
             psp_payment_method_id: "pending:pi_abc",
             status: "active")
      allow(Payments::Gateway).to receive(:fetch_payment_method).and_return(
        brand: "mastercard", last4: "4444", exp_month: 1, exp_year: 2029
      )

      payload = {
        "type" => "payment_intent.succeeded",
        "data" => {
          "object" => {
            "id" => "pi_abc",
            "status" => "succeeded",
            "customer" => "cus_late",
            "payment_method" => "pm_mc_4444",
            "metadata" => { "out_trade_no" => "STRIPE-OT-1" }
          }
        }
      }
      dispatch(provider: "stripe", verified_payload: payload,
                           signing_merchant_id: "acct_tenant_a")

      pm = Payments::PaymentMethod.find_by!(psp_payment_method_id: "pm_mc_4444")
      expect(pm.last4).to eq("4444")
      expect(stripe_payment.reload.psp_transaction_id).to eq("pi_abc")
    end
  end

  describe "PSP-reported settlement time (M6)" do
    it "stamps paid_at from WeChat's success_time rather than local processing time" do
      wechat_payment
      payload = {
        "out_trade_no" => "WX-OT-1",
        "transaction_id" => "TXN-TIME",
        "trade_state" => "SUCCESS",
        "success_time" => "2026-07-12T23:50:00+08:00"
      }

      dispatch(provider: "wechat_pay", verified_payload: payload)

      expect(wechat_payment.reload.paid_at.to_date).to eq(Date.new(2026, 7, 12))
    end

    it "stamps paid_at from Alipay's gmt_payment rather than local processing time" do
      alipay_payment
      payload = {
        "out_trade_no" => "AL-OT-1",
        "trade_no" => "TXN-TIME-A",
        "trade_status" => "TRADE_SUCCESS",
        "gmt_payment" => "2026-07-12 23:50:00"
      }

      dispatch(provider: "alipay", verified_payload: payload)

      expect(alipay_payment.reload.paid_at.to_date).to eq(Date.new(2026, 7, 12))
    end

    it "parses Alipay's gmt_payment as Beijing local time, not the app's UTC Time.zone (C)" do
      alipay_payment
      payload = {
        "out_trade_no" => "AL-OT-1",
        "trade_no" => "TXN-TIME-TZ",
        "trade_status" => "TRADE_SUCCESS",
        "gmt_payment" => "2026-07-13 23:30:00"
      }

      dispatch(provider: "alipay", verified_payload: payload)

      expect(alipay_payment.reload.paid_at).to be_within(1.second).of(Time.utc(2026, 7, 13, 15, 30, 0))
    end
  end

  describe "Stripe payment_intent.succeeded paid_at uses capture time, not intent creation time (B)" do
    let(:pi_order) { create(:payment_order, external_ref: "pi-cap", amount: 30.00, subject: "s") }
    let!(:pi_payment) do
      create(:payment, payment_order: pi_order, provider: "stripe", flow: "card",
                                out_trade_no: "PI-CAP-1", amount: 30.00, status: "pending")
    end
    let(:old_created)   { 5.days.ago.to_i }
    let(:fresh_capture)  { Time.current.to_i }

    it "rejects a capture in a different currency even when the numeric amount matches" do
      payload = { "type" => "payment_intent.succeeded", "data" => { "object" => {
        "id" => "pi_wrong_currency", "amount_received" => 3000, "currency" => "eur",
        "metadata" => { "out_trade_no" => pi_payment.out_trade_no }
      } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(pi_payment.reload.status).to eq("pending")
      expect(pi_order.reload.status).to eq("pending")
    end

    it "uses the signed success event time when latest_charge has not been expanded" do
      settled_at = Time.utc(2026, 7, 14, 0, 3, 0)
      payload = { "type" => "payment_intent.succeeded", "created" => settled_at.to_i,
                  "data" => { "object" => {
                    "id" => "pi_event_time", "amount_received" => 3000, "currency" => "cny",
                    "created" => old_created, "latest_charge" => "ch_unexpanded",
                    "metadata" => { "out_trade_no" => pi_payment.out_trade_no }
                  } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(pi_payment.reload.paid_at).to eq(settled_at)
      expect(pi_order.reload.paid_at).to eq(settled_at)
    end

    it "prefers the expanded latest_charge object's created over the intent's own created" do
      payload = { "type" => "payment_intent.succeeded",
                  "data" => { "object" => { "id" => "pi_cap_1", "amount" => 3000, "created" => old_created,
                                            "latest_charge" => { "created" => fresh_capture },
                                            "metadata" => { "out_trade_no" => "PI-CAP-1" } } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(pi_payment.reload.paid_at).to be_within(2.seconds).of(Time.zone.at(fresh_capture))
    end

    it "falls back to charges.data[0].created when latest_charge is not expanded" do
      out_trade_no = "PI-CAP-2"
      order2 = create(:payment_order, external_ref: "pi-cap-2", amount: 30.00, subject: "s")
      create(:payment, payment_order: order2, provider: "stripe", flow: "card",
                                out_trade_no: out_trade_no, amount: 30.00, status: "pending")
      payload = { "type" => "payment_intent.succeeded",
                  "data" => { "object" => { "id" => "pi_cap_2", "amount" => 3000, "created" => old_created,
                                            "latest_charge" => "ch_unexpanded",
                                            "charges" => { "data" => [ { "created" => fresh_capture } ] },
                                            "metadata" => { "out_trade_no" => out_trade_no } } } }

      dispatch(provider: "stripe", verified_payload: payload)

      payment = Payments::Payment.unscoped_by_tenant.find_by(out_trade_no: out_trade_no)
      expect(payment.paid_at).to be_within(2.seconds).of(Time.zone.at(fresh_capture))
    end

    it "falls back to webhook-arrival time (never the intent's created) when no charge timestamp is present" do
      payload = { "type" => "payment_intent.succeeded",
                  "data" => { "object" => { "id" => "pi_cap_3", "amount" => 3000, "created" => old_created,
                                            "metadata" => { "out_trade_no" => "PI-CAP-1" } } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(pi_payment.reload.paid_at).to be_within(2.seconds).of(Time.current)
      expect(pi_payment.paid_at).not_to be_within(1.day).of(Time.zone.at(old_created))
    end
  end

  describe "zero-decimal Stripe webhook amounts (JPY) (C1)" do
    let(:jpy_order) do
      create(:payment_order, external_ref: "jpy-o1", amount: 1000.00, subject: "s", currency: "JPY")
    end
    let!(:jpy_payment) do
      create(:payment, payment_order: jpy_order, provider: "stripe", flow: "card",
                                out_trade_no: "JPY-OT-1", amount: 1000.00, status: "pending")
    end

    it "marks a JPY payment succeeded when the rescaled amount_received matches" do
      payload = { "type" => "payment_intent.succeeded",
                  "data" => { "object" => { "id" => "pi_jpy", "amount_received" => 1000,
                                            "metadata" => { "out_trade_no" => "JPY-OT-1" } } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(jpy_payment.reload.status).to eq("succeeded")
    end

    it "does NOT mark a JPY payment succeeded when the rescaled amount mismatches" do
      payload = { "type" => "payment_intent.succeeded",
                  "data" => { "object" => { "id" => "pi_jpy2", "amount_received" => 999,
                                            "metadata" => { "out_trade_no" => "JPY-OT-1" } } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(jpy_payment.reload.status).to eq("pending")
    end

    it "records a JPY dispute amount rescaled to canonical cents" do
      create(:payment, payment_order: jpy_order, provider: "stripe", flow: "card",
                                out_trade_no: "JPY-OT-2", amount: 1000.00, status: "succeeded",
                                psp_transaction_id: "pi_jpy_disputed")
      payload = { "type" => "charge.dispute.created",
                  "data" => { "object" => { "id" => "dp_jpy", "payment_intent" => "pi_jpy_disputed",
                                            "reason" => "fraudulent", "status" => "needs_response",
                                            "amount" => 1000 } } }

      dispatch(provider: "stripe", verified_payload: payload)

      expect(Payments::Dispute.unscoped_by_tenant.find_by(psp_dispute_id: "dp_jpy").amount).to eq(1000.00)
    end
  end
end
