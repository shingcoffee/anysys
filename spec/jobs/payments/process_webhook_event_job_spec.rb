# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::ProcessWebhookEventJob do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  let!(:account) { create(:payment_merchant_account, customer: customer, provider: "wechat_pay", merchant_id: "job-merchant") }

  let(:order) { create(:payment_order, external_ref: "job-o1", amount: 1.00, subject: "s") }
  let!(:payment) do
    create(:payment, payment_order: order, provider: "wechat_pay", flow: "qr",
           out_trade_no: "JOB-OT-1", amount: 1.00, status: "pending")
  end

  let!(:event) do
    create(:payment_webhook_event,
            provider: "wechat_pay", psp_event_id: "JOB-EVT-1", event_type: "TRANSACTION.SUCCESS",
            status: "received", signing_merchant_id: account.merchant_id,
            payload: Payments::WebhookEvent.payload_with_verification(
              { "out_trade_no" => "JOB-OT-1", "transaction_id" => "TXN-JOB", "trade_state" => "SUCCESS" },
              signing_account_id: account.id))
  end

  describe "#perform" do
    it "processes the event via HandleWebhook and marks it processed with customer_id" do
      described_class.new.perform(event.id, nil)

      expect(payment.reload.status).to eq("succeeded")
      expect(event.reload.status).to eq("processed")
      expect(event.customer_id).to eq(customer.id)
    end

    it "is a no-op for an already-processed event" do
      event.update!(status: "processed")
      allow(Payments::Activities::HandleWebhook).to receive(:call)

      described_class.new.perform(event.id, nil)

      expect(Payments::Activities::HandleWebhook).not_to have_received(:call)
    end

    it "does not dispatch HandleWebhook twice when two jobs overlap on the same event" do
      allow(Payments::Activities::HandleWebhook).to receive(:call).and_call_original

      described_class.new.perform(event.id, nil)
      described_class.new.perform(event.id, nil)

      expect(Payments::Activities::HandleWebhook).to have_received(:call).once
      expect(event.reload.status).to eq("processed")
    end

    it "does not add an event transaction around handler work or dispatch a reentrant overlapping job" do
      baseline_depth = ActiveRecord::Base.connection.open_transactions
      calls = 0
      allow(Payments::Activities::HandleWebhook).to receive(:call) do
        calls += 1
        expect(ActiveRecord::Base.connection.open_transactions).to eq(baseline_depth)
        expect(event.reload.processing?).to be(true)
        described_class.new.perform(event.id, account.merchant_id, account.id)
        Current.customer = customer
      end

      described_class.new.perform(event.id, account.merchant_id, account.id)

      expect(calls).to eq(1)
      expect(event.reload.status).to eq("processed")
      expect(event.processing?).to be(false)
    end

    it "releases a failed projection's lease and never marks it processed" do
      allow(Payments::Activities::HandleWebhook).to receive(:call).and_raise(Payments::Errors::TransportError, "provider down")

      expect { described_class.new.perform(event.id, account.merchant_id, account.id) }
        .to raise_error(Payments::Errors::TransportError)

      expect(event.reload.status).to eq("received")
      expect(event.processed_at).to be_nil
      expect(event.processing?).to be(false)
      expect(Current.customer).to be_nil
    end

    it "settles a received event after its verified merchant label changes" do
      old_merchant = account.merchant_id
      payment.update!(prepay_payload: { Payments::Payment::ATTEMPT_CONTEXT_KEY => {
        merchant_account_id: account.id, merchant_id: old_merchant, mode: account.mode
      } })
      account.update!(merchant_id: "renamed-after-verify", status: "disabled")

      described_class.new.perform(event.id, old_merchant, account.id)

      expect(payment.reload.status).to eq("succeeded")
      expect(event.reload.status).to eq("processed")
      expect(event.signing_merchant_id).to eq(old_merchant)
    end

    it "leaves a missing verified account retryable instead of consuming the event" do
      event.update!(payload: Payments::WebhookEvent.payload_with_verification(event.verified_payload, signing_account_id: -1))

      expect { described_class.new.perform(event.id, event.signing_merchant_id, -1) }
        .to raise_error(Payments::Errors::CredentialsMissing)

      expect(event.reload.status).to eq("received")
      expect(event.processed_at).to be_nil
    end

    it "is a no-op when the event no longer exists" do
      expect { described_class.new.perform(-1, nil) }.not_to raise_error
    end

    it "rejects a conflicting queued account identity without settling the payment" do
      expect {
        described_class.new.perform(event.id, account.merchant_id, account.id + 1)
      }.to raise_error(Payments::Errors::SignatureInvalid)
      expect(payment.reload.status).to eq("pending")
      expect(event.reload.status).to eq("received")
    end

    it "fails closed when the verified account identity was not persisted" do
      event.update!(payload: event.verified_payload)
      expect {
        described_class.new.perform(event.id, account.merchant_id)
      }.to raise_error(Payments::Errors::SignatureInvalid)
      expect(payment.reload.status).to eq("pending")
    end

    it "settles an already received event after its original account is disabled" do
      payment.update!(prepay_payload: { Payments::Payment::ATTEMPT_CONTEXT_KEY => {
        merchant_account_id: account.id, merchant_id: account.merchant_id, mode: account.mode
      } })
      account.update!(status: "disabled")

      described_class.new.perform(event.id, account.merchant_id, account.id)

      expect(payment.reload.status).to eq("succeeded")
      expect(event.reload.signing_account_id).to eq(account.id)
    end
  end

  describe "retries and dead-letter" do
    it "dead-letters the event as failed after exhausting all retry attempts" do
      allow(Payments::Activities::HandleWebhook).to receive(:call).and_raise(StandardError, "boom")

      perform_enqueued_jobs do
        described_class.perform_later(event.id, account.merchant_id, account.id)
      end

      expect(event.reload.status).to eq("failed")
      expect(Payments::Activities::HandleWebhook).to have_received(:call).exactly(described_class::ATTEMPTS).times
      expect(Payments::Activities::HandleWebhook).to have_received(:call).with(
        provider: "wechat_pay", verified_payload: event.verified_payload,
        signing_merchant_id: account.merchant_id, signing_account_id: account.id
      ).exactly(described_class::ATTEMPTS).times
    end
  end

  describe "Current is reset between runs (no tenant bleed)" do
    it "resets Current.customer to nil after processing an event" do
      described_class.new.perform(event.id, nil)

      expect(Current.customer).to be_nil
    end

    it "resets Current.customer to nil even on the no-op path (event no longer exists)" do
      Current.customer = customer

      described_class.new.perform(-1, nil)

      expect(Current.customer).to be_nil
    end

    it "does not leak one event's tenant into the next event processed in the same worker thread" do
      other_customer = create(:customer)
      Current.customer = other_customer
      other_order = create(:payment_order, customer: other_customer, external_ref: "job-o2", amount: 2.00, subject: "s")
      other_payment = create(:payment, customer: other_customer, payment_order: other_order, provider: "wechat_pay", flow: "qr",
                             out_trade_no: "JOB-OT-2", amount: 2.00, status: "pending")
      other_account = create(:payment_merchant_account, customer: other_customer, provider: "wechat_pay", merchant_id: "other-job-merchant")
      other_event = create(:payment_webhook_event,
                           provider: "wechat_pay", psp_event_id: "JOB-EVT-2", event_type: "TRANSACTION.SUCCESS",
                            status: "received", signing_merchant_id: other_account.merchant_id,
                            payload: Payments::WebhookEvent.payload_with_verification(
                              { "out_trade_no" => "JOB-OT-2", "transaction_id" => "TXN-JOB-2", "trade_state" => "SUCCESS" },
                              signing_account_id: other_account.id))
      Current.reset

      # Process the first event (customer, via `payment`'s order) without ever
      # pre-setting Current — the job/HandleWebhook must resolve tenant from
      # the payment itself, and must not carry a stale Current.customer into
      # the second job run on the same (simulated) worker thread.
      described_class.new.perform(event.id, nil)
      expect(event.reload.customer_id).to eq(customer.id)

      described_class.new.perform(other_event.id, nil)

      expect(other_event.reload.customer_id).to eq(other_customer.id)
      expect(other_payment.reload.status).to eq("succeeded")
      # First event's tenant binding is untouched by the second run.
      expect(event.reload.customer_id).to eq(customer.id)
      expect(Current.customer).to be_nil
    end
  end
end
