# frozen_string_literal: true
require "rails_helper"
require_relative "../services/billing/partition_b_helpers"

RSpec.describe BillingMailer do
  include BillingPartitionBHelpers
  before { allow_any_instance_of(described_class).to receive(:admin_email_for).and_return("admin@example.test") }

  it "uses the issued invoice's plan identity rather than the edited catalog" do
    aggregate = billing_aggregate
    aggregate.fetch(:plan).update!(name: "Renamed catalog")
    mail = described_class.invoice_issued(aggregate.fetch(:invoice))
    expect(mail.subject).to include(aggregate.fetch(:invoice).number)
    expect(mail.html_part.body.to_s).to include(aggregate.fetch(:invoice).terms_snapshot.fetch("name"))
    expect(mail.html_part.body.to_s).not_to include("Renamed catalog")
  end

  it "renders asynchronous notices in the purchasing tenant's locale" do
    aggregate = billing_aggregate
    aggregate.fetch(:tenant).update!(locale: "zh-CN")
    mail = described_class.invoice_issued(aggregate.fetch(:invoice))
    expected = I18n.with_locale(:"zh-CN") { I18n.t("billing_mailer.invoice_issued.subject", number: aggregate.fetch(:invoice).number, amount: Billing::CurrencyResolver.format(10_000, "USD")) }
    expect(mail.subject).to eq(expected)
  end

  it "persists a deduplicated notice receipt instead of mailing inside invoice transitions" do
    aggregate = billing_aggregate
    invoice = aggregate.fetch(:invoice)
    expect { 2.times { Billing::Notifier.invoice_issued(invoice) } }.not_to change(Billing::Notice, :count)
    expect(Billing::Notice.find_by!(event_key: "invoice_issued:#{invoice.id}").state).to eq("pending")
  end
end
