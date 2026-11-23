# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::OneTimeProviderTilesComponent, type: :component do
  let(:post_url) { "/12345678/admin/settings/billing/invoices/11/one_time_payment" }

  def render_tiles(**options)
    render_inline described_class.new(
      providers: [{ key: "stripe" }, { key: "alipay" }],
      currency: "USD",
      post_url: post_url,
      **options
    )
  end

  it "renders the empty state when no enabled provider is available" do
    render_tiles(providers: [])
    expect(page).to have_text("No one-time payment provider is available")
    expect(page).to have_text("No configured provider can collect a one-time payment in USD.")
    expect(page).not_to have_css("ul[role='list']")
    expect(page).not_to have_css("form")
  end

  it "renders the empty state when every provider is disabled" do
    render_tiles(providers: [{ key: "alipay", enabled: false }])
    expect(page).to have_text("No one-time payment provider is available")
    expect(page).not_to have_css("form")
  end

  it "posts the selected provider without a turbo visit" do
    render_tiles
    expect(page).to have_css("ul[role='list'].sm\\:grid-cols-2.xl\\:grid-cols-3")
    expect(page).to have_css('form[action="/12345678/admin/settings/billing/invoices/11/one_time_payment"][data-turbo="false"]')
    expect(page).to have_css('input[name="one_time_payment[provider]"][value="stripe"]', visible: :all)
    expect(page).to have_button("Credit / Debit Card (Stripe)")
    expect(page).to have_text("Pay this invoice once")
    expect(page).not_to have_css('input[name="one_time_payment[invoice_id]"]', visible: :all)
  end

  it "includes the invoice id and uses two columns in the dialog layout" do
    render_tiles(invoice_id: 11, columns: 2)
    expect(page).to have_css("ul[role='list'].sm\\:grid-cols-2")
    expect(page).not_to have_css("ul.xl\\:grid-cols-3")
    expect(page).to have_css('input[name="one_time_payment[invoice_id]"][value="11"]', visible: :all)
  end

  it "highlights the active provider without a submit control" do
    render_tiles(selected_key: "stripe", providers: [{ key: "stripe" }, { key: "paypal" }])
    expect(page).to have_css(".border-accent.ring-accent", text: "Credit / Debit Card (Stripe)")
    expect(page).to have_text("One-time")
    expect(page).not_to have_css('input[name="one_time_payment[provider]"][value="stripe"]', visible: :all)
    expect(page).to have_css('input[name="one_time_payment[provider]"][value="paypal"]', visible: :all)
  end

  it "keeps a mixed disabled provider explanatory rather than actionable" do
    render_tiles(providers: [
      { key: "stripe" },
      { key: "alipay", enabled: false, reason_key: "settings_billing.payment_methods.currency_incompatible" }
    ])
    expect(page).to have_text("cannot collect invoices in USD")
    expect(page).to have_css("form")
    expect(page).not_to have_css('input[name="one_time_payment[provider]"][value="alipay"]', visible: :all)
  end

  it "localizes the empty hint in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_tiles(providers: [])
      expect(page).to have_text("暂无可用的单次支付服务商")
      expect(page).to have_text("尚无已配置的支付服务商支持收取 USD 单次付款。")
      expect(page).not_to have_css(".translation_missing")
    end
  end
end
