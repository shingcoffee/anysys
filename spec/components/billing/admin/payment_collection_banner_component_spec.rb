# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::PaymentCollectionBannerComponent, type: :component do
  let(:invoice) { double(status: "open", settlement_review_code: nil) }
  let(:next_attempt_at) { Time.zone.local(2026, 10, 28, 9, 0) }

  def build_banner(**overrides)
    described_class.new(
      invoice: invoice,
      collection: {},
      customer_id: 12345678,
      collection_state: "ready",
      collection_tone: [:clock, "bg-info-subtle text-info"],
      stripe_recovery: false,
      recovery_data: {},
      show_retry: false,
      retry_path: "/12345678/admin/settings/billing/invoices/1/payment",
      result_path: "/12345678/admin/settings/billing/invoices/1",
      **overrides
    )
  end

  def render_banner(**overrides)
    render_inline build_banner(**overrides)
  end

  it "does not render a settled paid invoice without a settlement review" do
    invoice = double(status: "paid", settlement_review_code: nil)
    component = build_banner(invoice: invoice, collection_state: "settled")
    expect(component.render?).to be(false)
    render_inline component
    expect(page).not_to have_css("section")
  end

  it "renders a paid invoice that still needs settlement review" do
    invoice = double(status: "paid", settlement_review_code: "duplicate_capture")
    render_banner(invoice: invoice, collection_state: "settled",
      collection_tone: [:check, "bg-success-subtle text-success"])
    expect(page).to have_css("section[aria-labelledby='invoice-collection-heading']")
    expect(page).to have_css("#invoice-collection-heading", visible: :all)
    expect(page).not_to have_css("header.card-header")
    expect(page).to have_text("Payment has been recorded, but its subscription effect requires platform review.")
    expect(page).not_to have_text("Authorized collection mode")
    expect(page).not_to have_text("Recorded collection mode")
    expect(page).not_to have_text("Failed collection attempts")
  end

  it "offers retry and the next attempt on an open invoice" do
    render_banner(collection: { next_attempt_at: next_attempt_at }, show_retry: true)
    expect(page).to have_button("Pay invoice")
    expect(page).to have_text("Next scheduled attempt")
    expect(page).to have_text("October 28, 2026")
    expect(page).to have_link("Payment methods", href: "/12345678/admin/settings/billing/payment_methods")
    expect(page).not_to have_button("Complete payment authentication")
    expect(page).not_to have_text("Authorized collection mode")
  end

  it "mounts Stripe recovery on an uncollectible invoice without operator plumbing" do
    invoice = double(status: "uncollectible", settlement_review_code: nil)
    render_banner(
      invoice: invoice,
      collection_state: "requires_action",
      collection_tone: [:alert, "bg-warning-subtle text-warning"],
      stripe_recovery: true,
      recovery_data: { controller: "payments--stripe-card", "payments--stripe-card-client-secret-value" => "pi_secret" }
    )
    expect(page).to have_button("Complete payment authentication")
    expect(page).to have_css('[data-payments--stripe-card-client-secret-value="pi_secret"]')
    expect(page).not_to have_button("Pay invoice")
    expect(page).not_to have_text("Authorized collection mode")
    expect(page).not_to have_text("Recorded collection mode")
    expect(page).not_to have_text("Failed collection attempts")
  end

  it "does not advertise one-time payment unless the caller asks for it" do
    render_banner
    expect(page).not_to have_link("One-time payment")
  end

  it "links to one-time payment as the primary action when retry is unavailable" do
    render_banner(show_one_time_payment: true, one_time_payment_path: "/12345678/admin/settings/billing/invoices/1/one_time_payment")
    expect(page).to have_link("One-time payment", href: "/12345678/admin/settings/billing/invoices/1/one_time_payment", class: "btn-primary")
    expect(page).not_to have_css("form", text: "One-time payment")
    expect(page).not_to have_button("One-time payment")
  end

  it "keeps retry primary and demotes one-time payment when both are offered" do
    render_banner(show_retry: true, show_one_time_payment: true,
      one_time_payment_path: "/12345678/admin/settings/billing/invoices/1/one_time_payment")
    expect(page).to have_button("Pay invoice")
    expect(page).to have_link("One-time payment", class: "btn-secondary")
  end
end
