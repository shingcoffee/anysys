# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Admin::DisputeTableComponent, type: :component do
  def dispute_double(status:, reason: "fraudulent", dispute_id: "dp_1", currency: "USD", amount: 5.00)
    order   = instance_double(Payments::Order, currency: currency)
    payment = instance_double(Payments::Payment, payment_order: order)
    instance_double(Payments::Dispute, provider: "stripe", psp_dispute_id: dispute_id,
                                       reason: reason, status: status, amount: amount,
                                       payment: payment,
                                       opened_at: Time.zone.local(2026, 5, 1, 9, 0))
  end

  it "renders dispute provider, id, reason, amount, and localized status" do
    render_inline(described_class.new(disputes: [dispute_double(status: "lost")]))

    expect(page).to have_text("Credit / Debit Card (Stripe)")
    expect(page).to have_text("dp_1")
    expect(page).to have_text(I18n.t("comp_payments.dispute_table.reasons.fraudulent"))
    expect(page).to have_text("$5.00")
    expect(page).to have_text(I18n.t("comp_payments.dispute_table.statuses.lost"))
    expect(page).to have_text(I18n.l(Time.zone.local(2026, 5, 1, 9, 0), format: :long))
  end

  it "localizes provider, status, and reason in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(disputes: [dispute_double(status: "lost")]))
      expect(page).to have_text("Credit / Debit Card (Stripe)")
      expect(page).to have_text(I18n.t("comp_payments.dispute_table.statuses.lost"))
      expect(page).to have_text(I18n.t("comp_payments.dispute_table.reasons.fraudulent"))
    end
  end

  it "formats a zero-decimal (JPY) dispute amount without the 100x canonical-cents inflation" do
    # Storage is always a major-unit decimal with two digits; for zero-decimal
    # currencies like JPY the fractional digits are still present (e.g. ¥100).
    render_inline(described_class.new(disputes: [dispute_double(status: "lost", currency: "JPY", amount: 100.00)]))

    expect(page).to have_text(Billing::CurrencyResolver.format(100, "JPY"))
    expect(page).to have_no_text(Billing::CurrencyResolver.format(10_000, "JPY"))
  end

  it "renders the empty state when there are no disputes" do
    render_inline(described_class.new(disputes: []))
    expect(page).to have_text("No disputes")
  end

  describe "#status_variant" do
    subject { described_class.new(disputes: []) }

    it { expect(subject.status_variant("won")).to eq(:success) }
    it { expect(subject.status_variant("lost")).to eq(:danger) }
    it { expect(subject.status_variant("under_review")).to eq(:warning) }
    it { expect(subject.status_variant("closed")).to eq(:default) }
    it { expect(subject.status_variant("open")).to eq(:warning) }
  end

  describe "#provider_label" do
    subject { described_class.new(disputes: []) }

    it "falls back to the raw key for an unknown provider" do
      expect(subject.provider_label("not_a_gateway")).to eq("not_a_gateway")
    end
  end

  describe "#status_label" do
    subject { described_class.new(disputes: []) }

    it "falls back to the raw key for an unknown status" do
      expect(subject.status_label("unknown")).to eq("unknown")
    end
  end

  describe "#reason_label" do
    subject { described_class.new(disputes: []) }

    it "falls back to the raw key for an unknown reason" do
      expect(subject.reason_label("leaked_reason")).to eq("leaked_reason")
    end

    it "localizes a PayPal SCREAMING_SNAKE reason" do
      expect(subject.reason_label("MERCHANDISE_OR_SERVICE_NOT_RECEIVED")).to eq(
        I18n.t("comp_payments.dispute_table.reasons.MERCHANDISE_OR_SERVICE_NOT_RECEIVED")
      )
    end

    it "localizes a PayPal reason in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        expect(subject.reason_label("MERCHANDISE_OR_SERVICE_NOT_RECEIVED")).to eq(
          I18n.t("comp_payments.dispute_table.reasons.MERCHANDISE_OR_SERVICE_NOT_RECEIVED")
        )
      end
    end

    it "returns the em dash for a blank reason" do
      expect(subject.reason_label(nil)).to eq(I18n.t("common.labels.em_dash"))
    end
  end
end
