# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::ResultComponent, type: :component do
  let(:order) { instance_double(Payments::Order, external_ref: "ORDER-7") }

  it "renders the success view with the injected Return CTA" do
    payment = instance_double(Payments::Payment, status: "succeeded", payment_order: order)
    render_inline(described_class.new(payment: payment, return_path: "/42/forms/thanks"))

    expect(page).to have_text("Payment successful")
    expect(page).to have_text("Order #ORDER-7")
    expect(page).to have_link("Return", href: "/42/forms/thanks")
  end

  it "renders the pending view when payment is still pending" do
    payment = instance_double(Payments::Payment, status: "pending", payment_order: order)
    render_inline(described_class.new(payment: payment, return_path: "/42"))

    expect(page).to have_text("Payment pending")
    expect(page).to have_text("Status: Pending")
  end

  it "localizes the pending status in zh-CN" do
    payment = instance_double(Payments::Payment, status: "pending", payment_order: order)
    I18n.with_locale(:"zh-CN") do
      render_inline(described_class.new(payment: payment, return_path: "/42"))
      expect(page).to have_text(I18n.t("comp_payments.result.pending_title"))
      expect(page).to have_text("#{I18n.t("comp_payments.result.status_prefix")}#{I18n.t("comp_payments.result.statuses.pending")}")
    end
  end

  it "renders the failure view when payment is not succeeded" do
    payment = instance_double(Payments::Payment, status: "failed", payment_order: order)
    render_inline(described_class.new(payment: payment, return_path: "/42"))

    expect(page).to have_text("Payment not completed")
    expect(page).to have_text("Status: Failed")
    expect(page).to have_link("Return", href: "/42")
  end

  describe "#status_label" do
    it "falls back to the raw key for an unknown status" do
      payment = instance_double(Payments::Payment, status: "unknown", payment_order: order)
      expect(described_class.new(payment: payment, return_path: "/42").status_label).to eq("unknown")
    end
  end
end
