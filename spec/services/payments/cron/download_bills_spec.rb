# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Cron::DownloadBills do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:payment_module) { enable_module!("payment", customer, name: "Payments") }

  before { Current.customer = customer }

  def create_account(provider:, merchant_id:, status: "active", mode: "sandbox")
    create(:payment_merchant_account, customer: customer, provider: provider, mode: mode,
           merchant_id: merchant_id, status: status)
  end

  it "calls Reconcile.call once per active merchant account" do
    acc1 = create_account(provider: "alipay", merchant_id: "M1", mode: "sandbox")
    acc2 = create_account(provider: "wechat_pay", merchant_id: "M2", mode: "sandbox")
    create_account(provider: "alipay", merchant_id: "M3", mode: "production", status: "disabled")

    bill_date = Date.new(2026, 4, 20)

    expect(Payments::Activities::Reconcile).to receive(:call)
      .with(customer: customer, provider: acc1.provider, bill_date: bill_date, merchant_account: acc1).once
    expect(Payments::Activities::Reconcile).to receive(:call)
      .with(customer: customer, provider: acc2.provider, bill_date: bill_date, merchant_account: acc2).once

    described_class.perform(bill_date: bill_date)
  end

  it "swallows Payments::Errors::Error and continues processing other accounts" do
    create_account(provider: "alipay", merchant_id: "B1", mode: "sandbox")
    create_account(provider: "wechat_pay", merchant_id: "G1", mode: "sandbox")

    call_count = 0
    allow(Payments::Activities::Reconcile).to receive(:call) do |**_|
      call_count += 1
      raise Payments::Errors::TransportError, "timeout" if call_count == 1
      nil
    end

    expect { described_class.perform(bill_date: Date.new(2026, 4, 20)) }.not_to raise_error
    expect(call_count).to eq(2)
  end

  it "does not download bills when the Payments module is disabled" do
    create_account(provider: "alipay", merchant_id: "OFF-1", mode: "sandbox")
    FeatureModules::CustomerAssignment.find_by!(
      customer: customer, feature_module: payment_module
    ).update!(status: :suspended)

    expect(Payments::Activities::Reconcile).not_to receive(:call)
    described_class.perform(bill_date: Date.new(2026, 4, 20))
  end
end
