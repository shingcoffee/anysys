# frozen_string_literal: true

require "rails_helper"

# Payments::HandoffCompletion bridges a resolved Payment back to the
# page → payment handoff that launched it. When the shopper arrived via a
# FeatureModules handoff and the payment succeeded, it drives
# FeatureModules::Complete (validate output, resolve the author's exit_target,
# clear the session). It returns nil — meaning "just render the result page" —
# for every case where there is no active payment handoff to complete.
RSpec.describe Payments::HandoffCompletion do
  let_it_be(:customer) { create(:customer) }

  let!(:fm) { enable_module!("payment", customer, name: "Payments", configuration: {}.to_json) }
  let(:landing_page) { create(:page, customer: customer, launched: true) }

  let(:order) do
    create(:payment_order,
           customer: customer, external_ref: described_class.order_reference(token),
           amount: 100.00, currency: "CNY", subject: "Order", status: "pending")
  end
  let(:token) { "tok-#{SecureRandom.hex(8)}" }
  let(:payment) do
    create(:payment,
           customer: customer, payment_order: order, provider: "alipay", flow: "qr",
           out_trade_no: "trade-#{SecureRandom.hex(6)}", amount: 100.00, status: "succeeded",
           paid_at: Time.current, handoff_token: token)
  end

  before do
    allow_any_instance_of(FeatureModules::Module)
      .to receive(:registration_class).and_return(FeatureModules::Payment::Registration)
    Current.customer = customer
  end

  after { Current.customer = nil }

  def session_with_payment_invocation(tok: token)
    {
      feature_module_invocation: {
        module_key: "payment", customer_id: customer.id, token: tok,
        input: { amount: 100.00, currency: "CNY", subject: "Order" },
        exit_target: { kind: "page", page_id: landing_page.id },
        started_at: Time.current.iso8601
      }
    }
  end

  describe ".call with an active payment invocation and a succeeded payment" do
    it "completes the handoff: resolves the author's exit_target, clears the session, returns redirect + flash" do
      session = session_with_payment_invocation

      result = described_class.call(session: session, customer: customer, payment: payment)

      expect(result[:redirect_to]).to eq("/#{customer.id}/page/#{landing_page.public_uuid}")
      expect(result[:flash]).to include(
        feature_module_result: hash_including(module_key: "payment")
      )
      expect(session).not_to have_key(:feature_module_invocation)
    end

    it "maps the payment into the module output contract (payment_reference/status/paid_at)" do
      session = session_with_payment_invocation

      expect(FeatureModules::Complete).to receive(:call).with(
        hash_including(
          module_key: "payment",
          output: hash_including(
            payment_reference: payment.out_trade_no,
            status: "succeeded"
          )
        )
      ).and_call_original

      described_class.call(session: session, customer: customer, payment: payment)
    end
  end

  describe ".call when there is nothing to complete" do
    it "does not complete a cheaper unrelated order even when its payment carries the current token" do
      order.update!(external_ref: "unrelated-cheap", amount: 0.01)
      payment.update!(amount: 0.01)
      session = session_with_payment_invocation

      expect(described_class.call(session: session, customer: customer, payment: payment)).to be_nil
      expect(session).to have_key(:feature_module_invocation)
    end

    it "does not complete when the expected order's amount differs from the invocation" do
      order.update!(amount: 0.01)
      payment.update!(amount: 0.01)
      session = session_with_payment_invocation

      expect(described_class.call(session: session, customer: customer, payment: payment)).to be_nil
      expect(session).to have_key(:feature_module_invocation)
    end

    it "does not complete a currency substitution" do
      order.update!(currency: "USD")
      expect(described_class.call(session: session_with_payment_invocation, customer: customer, payment: payment)).to be_nil
    end

    it "does not complete an underpaid attempt on an otherwise matching order" do
      payment.update!(amount: 0.01)
      expect(described_class.call(session: session_with_payment_invocation, customer: customer, payment: payment)).to be_nil
    end

    it "returns nil for a non-succeeded payment even with an active invocation" do
      payment.update!(status: "failed")
      session = session_with_payment_invocation

      expect(described_class.call(session: session, customer: customer, payment: payment)).to be_nil
      expect(session).to have_key(:feature_module_invocation) # invocation left intact
    end

    it "returns nil when there is no invocation in the session" do
      expect(described_class.call(session: {}, customer: customer, payment: payment)).to be_nil
    end

    it "returns nil when the succeeded payment was charged by a different invocation (token mismatch)" do
      # The core protection: a shopper points the result URL at some other
      # succeeded payment (guessed by its enumerable id). That payment carries a
      # different session's token, so it cannot complete this invocation.
      payment.update!(handoff_token: "someone-elses-token")
      session = session_with_payment_invocation # carries `token`, not "someone-elses-token"

      expect(described_class.call(session: session, customer: customer, payment: payment)).to be_nil
      expect(session).to have_key(:feature_module_invocation)
    end

    it "returns nil when the succeeded payment carries no handoff_token at all" do
      payment.update!(handoff_token: nil)
      session = session_with_payment_invocation

      expect(described_class.call(session: session, customer: customer, payment: payment)).to be_nil
    end

    it "returns nil when the active invocation belongs to a different module" do
      session = { feature_module_invocation: {
        module_key: "authentication", customer_id: customer.id,
        exit_target: nil, started_at: Time.current.iso8601
      } }

      expect(described_class.call(session: session, customer: customer, payment: payment)).to be_nil
      expect(session).to have_key(:feature_module_invocation)
    end

    it "returns nil (does not raise) when the session invocation is for another tenant" do
      session = { feature_module_invocation: {
        module_key: "payment", customer_id: -999,
        exit_target: nil, started_at: Time.current.iso8601
      } }

      expect {
        expect(described_class.call(session: session, customer: customer, payment: payment)).to be_nil
      }.not_to raise_error
    end
  end
end
