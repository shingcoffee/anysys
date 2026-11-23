require "rails_helper"

RSpec.describe Payments::CredentialResolver do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  it "returns the active account for provider+mode" do
    acc = create(:payment_merchant_account, :wechat_pay, :production,
                 merchant_id: "m1", status: "active")
    expect(described_class.call(customer: customer, provider: "wechat_pay", mode: "production")).to eq(acc)
  end

  it "raises CredentialsMissing when absent" do
    expect {
      described_class.call(customer: customer, provider: "alipay", mode: "production")
    }.to raise_error(Payments::Errors::CredentialsMissing)
  end

  it "raises CredentialsMissing when disabled" do
    create(:payment_merchant_account, :alipay, :production, :disabled, merchant_id: "a")
    expect {
      described_class.call(customer: customer, provider: "alipay", mode: "production")
    }.to raise_error(Payments::Errors::CredentialsMissing)
  end

  it "can resolve by [provider, merchant_id] for webhooks (cross-tenant)" do
    create(:payment_merchant_account, :wechat_pay, :production,
           merchant_id: "wx123", status: "active")
    # Switch tenant — the lookup must still find the account
    other_customer = create(:customer)
    Current.customer = other_customer
    acc = described_class.by_merchant_id(provider: "wechat_pay", merchant_id: "wx123")
    expect(acc.customer_id).to eq(customer.id)
  end

  it "raises TenantNotFound for unknown merchant_id" do
    expect {
      described_class.by_merchant_id(provider: "alipay", merchant_id: "nope")
    }.to raise_error(Payments::Errors::TenantNotFound)
  end

  describe ".for_psp_operation" do
    let(:historical) { create(:payment_merchant_account, :stripe, customer: customer, status: "disabled", merchant_id: "historical-route") }
    let(:payment) do
      create(:payment, customer: customer, provider: "stripe", psp_transaction_id: "pi_historical", prepay_payload: {
        Payments::Payment::ATTEMPT_CONTEXT_KEY => {
          "provider" => "stripe", "merchant_account_id" => historical.id,
          "merchant_id" => historical.merchant_id, "mode" => historical.mode
        }
      })
    end

    it "resolves the exact historical account across environment mode changes" do
      payment
      create(:payment_merchant_account, :stripe, :production, customer: customer, merchant_id: "current-mode-route")
      allow(described_class).to receive(:default_mode).and_return("production")
      expect(described_class.for_psp_operation(provider: "stripe", psp_transaction_id: "pi_historical")).to eq(historical)
    end

    it "does not route an operation through another provider" do
      payment
      expect(described_class.for_psp_operation(provider: "paypal", psp_transaction_id: "pi_historical")).to be_nil
    end

    it "allows label/mode drift for historical lookup of the exact row, but rejects new writes" do
      record = payment
      historical.update!(merchant_id: "renamed-history", mode: "production")
      expect(described_class.for_psp_operation(provider: "stripe", psp_transaction_id: "pi_historical")).to eq(historical)
      expect(described_class.for_payment(customer: customer, payment: record)).to eq(historical)
      expect { described_class.for_payment(customer: customer, payment: record, historical: false) }
        .to raise_error(Payments::Errors::CredentialsMissing)
    end

    it "refuses a contradictory saved provider even when the record's provider matches the account" do
      record = payment
      context = record.attempt_context.merge("provider" => "paypal")
      record.update!(prepay_payload: { Payments::Payment::ATTEMPT_CONTEXT_KEY => context })
      expect { described_class.for_psp_operation(provider: "stripe", psp_transaction_id: "pi_historical") }
        .to raise_error(Payments::Errors::CredentialsMissing)
    end
  end
end
