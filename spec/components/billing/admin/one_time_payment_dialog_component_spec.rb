# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::OneTimePaymentDialogComponent, type: :component do
  let(:one_time_payment) do
    {
      kind: "unpaid_invoice",
      invoice_id: 19,
      invoice_number: "INV-12345678-00019",
      currency: "USD",
      amount_cents: 2400,
      period_start: Time.zone.local(2026, 9, 23),
      period_end: Time.zone.local(2026, 10, 23),
      due_at: Time.zone.local(2026, 10, 23),
      providers: [{ key: "stripe" }, { key: "paypal" }]
    }
  end

  def render_dialog(**overrides)
    render_inline described_class.new(
      one_time_payment: one_time_payment.merge(overrides.except(:error_message, :open)),
      customer_id: 12345678,
      post_url: "/12345678/admin/settings/billing/subscription/one_time_payment",
      open: overrides.fetch(:open, false),
      error_message: overrides[:error_message]
    )
  end

  it "summarizes the invoice and posts the chosen provider from the named dialog" do
    render_dialog
    dialog = page.find("dialog#one-time-payment-dialog", visible: :all)
    expect(dialog["aria-labelledby"]).to eq("one-time-payment-dialog-title")
    expect(dialog).to have_css("h2", text: "Make one-time payment", visible: :all)
    expect(dialog).to have_css("*", text: "$24.00 USD", visible: :all)
    expect(dialog).to have_css("*", text: "Outstanding invoice", visible: :all)
    expect(dialog).to have_css("*", text: "INV-12345678-00019", visible: :all)
    expect(dialog).to have_css("*", text: "September 23, 2026", visible: :all)
    expect(dialog).to have_css("*", text: "October 23, 2026", visible: :all)
    expect(dialog).to have_css("*", text: "This is a one-time payment for this invoice. Recurring auto-charge methods are unchanged.", visible: :all)
    expect(dialog).to have_css("*", text: "Choose a payment provider", visible: :all)
    expect(dialog).to have_css('input[name="one_time_payment[provider]"][value="stripe"]', visible: :all)
    expect(dialog).to have_css('input[name="one_time_payment[invoice_id]"][value="19"]', visible: :all)
    expect(dialog).to have_css('button[data-action="modal-dialog#close"]', text: "Cancel", visible: :all)
    expect(dialog).to have_css("ul[role='list'].sm\\:grid-cols-2", visible: :all)
  end

  it "falls back to the draft label when the invoice has no number" do
    render_dialog(invoice_number: nil, kind: "draft_initial")
    dialog = page.find("dialog#one-time-payment-dialog", visible: :all)
    expect(dialog).to have_css("*", text: "(draft)", visible: :all)
    expect(dialog).to have_css("*", text: "Initial subscription invoice", visible: :all)
  end

  it "surfaces an error alert inside the dialog" do
    render_dialog(error_message: "Provider was unavailable.")
    expect(page).to have_css('[role="alert"]', text: "Provider was unavailable.", visible: :all)
  end

  it "renders the empty provider state inside the dialog" do
    render_dialog(providers: [])
    dialog = page.find("dialog#one-time-payment-dialog", visible: :all)
    expect(dialog).to have_css("*", text: "No one-time payment provider is available", visible: :all)
    expect(dialog).not_to have_css("form", visible: :all)
  end

  it "localizes dialog copy in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_dialog
      dialog = page.find("dialog#one-time-payment-dialog", visible: :all)
      expect(dialog).to have_css("*", text: "单次支付当前费用", visible: :all)
      expect(dialog).to have_css("*", text: "待付账单", visible: :all)
      expect(dialog).to have_css("*", text: "选择支付服务商", visible: :all)
      expect(page).not_to have_css(".translation_missing")
    end
  end
end
