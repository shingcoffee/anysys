# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/data_migrations/payment_historical_bindings_v1")

RSpec.describe PaymentHistoricalBindingsV1 do
  let(:customer) { create(:customer) }
  let(:account) { create(:payment_merchant_account, :stripe, customer: customer, status: "disabled", merchant_id: "recorded-merchant") }

  def legacy_payment(**attributes)
    create(:payment, { customer: customer, provider: "stripe", status: "succeeded", flow: "card",
                      psp_transaction_id: "pi_old", prepay_payload: { "client_secret" => "keep-original" } }.merge(attributes))
  end

  def capture_evidence(payment, merchant_id: account.merchant_id)
    { "object" => "payment_intent", "id" => payment.psp_transaction_id,
      "metadata" => { "merchant_id" => merchant_id, "out_trade_no" => payment.out_trade_no } }
  end

  it "preflights then pins explicit recorded merchant evidence without changing financial/user data" do
    payment = legacy_payment
    payment.update!(raw_notify: capture_evidence(payment))
    before = payment.reload.attributes.except("prepay_payload")

    report = described_class.new.call
    expect(report["summary"]).to include("payments_to_bind" => 1, "unresolved" => 0)
    expect(payment.reload.merchant_account_id).to be_nil

    report = described_class.new.call(apply: true)
    expect(report["applied"]).to be(true)
    expect(payment.reload.attributes.except("prepay_payload")).to eq(before)
    expect(payment.prepay_payload["client_secret"]).to eq("keep-original")
    expect(payment.attempt_context).to include("provider" => "stripe", "merchant_account_id" => account.id,
                                             "review_reason" => "historical_identity_backfill")
    expect(Payments::CredentialResolver.for_payment(customer: customer, payment: payment)).to eq(account)
    expect(described_class.new.call["summary"]["payments_to_bind"]).to eq(0)
  end

  it "recovers payment and event identities from a previously verified ledger's explicit signer and operation IDs" do
    payment = legacy_payment(raw_notify: {})
    payload = { "id" => "evt_old", "type" => "payment_intent.succeeded",
                "data" => { "object" => capture_evidence(payment).except("metadata") } }
    event = create(:payment_webhook_event, provider: "stripe", psp_event_id: "evt_old", customer_id: nil,
                   signing_merchant_id: account.merchant_id, payload: payload, status: "received")

    report = described_class.new.call(apply: true)
    expect(report["summary"]).to include("events_to_bind" => 1, "payments_to_bind" => 1, "unresolved" => 0)
    expect(event.reload.signing_account_id).to eq(account.id)
    expect(event.status).to eq("received")
    expect(event.verified_payload).to eq(payload)
    expect(payment.reload.merchant_account_id).to eq(account.id)
  end

  it "does not guess from a sole customer/provider account" do
    account
    payment = legacy_payment(raw_notify: {})
    report = described_class.new.call
    expect(report["unresolved"]).to include(hash_including("kind" => "payment", "id" => payment.id))
    expect { described_class.new.call(apply: true) }.to raise_error(described_class::UnresolvedBindings)
    expect(payment.reload.merchant_account_id).to be_nil
  end

  it "rejects conflicting evidence and applies no other deterministic rows partially" do
    good = legacy_payment(psp_transaction_id: "pi_good")
    good.update!(raw_notify: capture_evidence(good))
    second = create(:payment_merchant_account, :stripe, :production, customer: customer, merchant_id: "contradictory-merchant")
    bad = legacy_payment(psp_transaction_id: "pi_conflict", prepay_payload: { "_attempt" => { "merchant_id" => account.merchant_id } })
    bad.update!(raw_notify: capture_evidence(bad, merchant_id: second.merchant_id))

    expect { described_class.new.call(apply: true) }.to raise_error(described_class::UnresolvedBindings)
    expect(good.reload.merchant_account_id).to be_nil
    expect(bad.reload.merchant_account_id).to be_nil
  end

  it "rejects foreign-tenant merchant evidence" do
    foreign = create(:payment_merchant_account, :stripe, customer: create(:customer), merchant_id: "foreign-merchant")
    payment = legacy_payment
    payment.update!(raw_notify: capture_evidence(payment, merchant_id: foreign.merchant_id))
    expect { described_class.new.call(apply: true) }.to raise_error(described_class::UnresolvedBindings)
  end

  it "rejects a contradictory existing verification envelope rather than trusting a formerly vendor-supplied key" do
    foreign = create(:payment_merchant_account, :stripe, customer: create(:customer))
    event = create(:payment_webhook_event, provider: "stripe", signing_merchant_id: account.merchant_id,
      payload: { "_anysys_verification" => { "merchant_account_id" => foreign.id } })
    expect { described_class.new.call(apply: true) }.to raise_error(described_class::UnresolvedBindings)
    expect(event.reload.signing_account_id).to eq(foreign.id)
  end

  it "completes a partial explicit account snapshot without requiring mutable historical labels to match" do
    payment = legacy_payment(prepay_payload: { "_attempt" => { "merchant_account_id" => account.id,
                                                            "merchant_id" => "former-label", "mode" => "production" } })
    described_class.new.call(apply: true)
    expect(payment.reload.attempt_context).to include("provider" => "stripe", "merchant_account_id" => account.id,
                                                    "merchant_id" => "former-label", "mode" => "production")
    expect(Payments::CredentialResolver.for_payment(customer: customer, payment: payment)).to eq(account)
  end

  it "does not bind raw notification evidence whose explicit operation IDs refer to another payment" do
    payment = legacy_payment
    payment.update!(raw_notify: { "object" => "payment_intent", "id" => "pi_other",
                                 "metadata" => { "merchant_id" => account.merchant_id, "out_trade_no" => "other-order" } })
    expect { described_class.new.call(apply: true) }.to raise_error(described_class::UnresolvedBindings)
  end

  it "rejects partially matching evidence whose other recorded PSP identity conflicts" do
    payment = legacy_payment
    payment.update!(raw_notify: capture_evidence(payment).merge("id" => "pi_conflicting"))
    expect { described_class.new.call(apply: true) }.to raise_error(described_class::UnresolvedBindings)
    expect(payment.reload.merchant_account_id).to be_nil
  end

  it "does not bless an event lacking its explicit recorded event ID" do
    account
    event = create(:payment_webhook_event, provider: "stripe", signing_merchant_id: account.merchant_id, payload: {})
    expect { described_class.new.call(apply: true) }.to raise_error(described_class::UnresolvedBindings)
    expect(event.reload.signing_account_id).to be_nil
  end

  {
    "alipay" => ->(merchant, payment) { { "app_id" => merchant.merchant_id, "out_trade_no" => payment.out_trade_no, "trade_no" => payment.psp_transaction_id } },
    "wechat_pay" => ->(merchant, payment) { { "resource" => { "mchid" => merchant.merchant_id, "out_trade_no" => payment.out_trade_no, "transaction_id" => payment.psp_transaction_id } } },
    "paypal" => ->(merchant, payment) { { "event_type" => "PAYMENT.CAPTURE.COMPLETED", "resource" => { "custom_id" => merchant.merchant_id, "invoice_id" => payment.out_trade_no, "id" => payment.psp_transaction_id } } }
  }.each do |provider, evidence|
    it "uses #{provider}'s native explicit merchant and payment identifiers" do
      merchant = create(:payment_merchant_account, provider.to_sym, customer: customer, status: "disabled")
      payment = legacy_payment(provider: provider)
      payment.update!(raw_notify: evidence.call(merchant, payment))
      described_class.new.call(apply: true)
      expect(payment.reload.merchant_account_id).to eq(merchant.id)
      expect(payment.status).to eq("succeeded")
    end
  end
end
