# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::CustomerPaymentMethodsComponent, type: :component do
  def method_row(id, status, **attributes)
    double(id: id, to_param: id.to_s, status: status, provider: "alipay", is_default: false, display_label: nil,
      authorized_at: nil, revocation_state: "none", **attributes)
  end

  def render_methods(methods, **options)
    render_inline described_class.new(payment_methods: methods, available_providers: ["alipay"],
      provider_options: [{ key: "alipay", setup_kind: :redirect }], currency: "CNY", customer_id: 12345678, **options)
  end

  it "distinguishes local active status from verified charge readiness" do
    blocked = method_row(1, "active", is_default: true)
    ready = method_row(2, "active")
    render_methods([blocked, ready], payment_method_readiness: {
      1 => { charge_ready: false, reason_key: "settings_billing.payment_methods.gateway_unavailable" },
      2 => { charge_ready: true, default_eligible: true }
    })
    within('[data-payment-method-id="1"]') do
      expect(page).to have_text("Default")
      expect(page).to have_text("currently unavailable")
      expect(page).not_to have_button("Make Default")
    end
    within('[data-payment-method-id="2"]') { expect(page).to have_button("Make Default") }
  end

  it "renders all method states with the plan's removal and continuation semantics" do
    render_methods(%w[removed failed pending active].each_with_index.map { |state, index| method_row(index + 1, state) })
    expect(page.all('[data-payment-method-id]').map { |row| row['data-payment-method-id'] }).to eq(%w[4 3 2 1])
    within('[data-payment-method-id="3"]') do
      expect(page).to have_link("Continue authorization", href: "/12345678/admin/settings/billing/payment_methods/3/authorization")
      expect(page).to have_button("Remove")
      expect(page).not_to have_button("Make Default")
    end
    within('[data-payment-method-id="2"]') { expect(page).to have_button("Remove") }
    within('[data-payment-method-id="1"]') do
      expect(page).to have_link("Reauthorize")
      expect(page).not_to have_button("Remove")
    end
  end

  it "lists active methods first and groups the rest under one heading" do
    render_methods([method_row(1, "failed"), method_row(2, "active")])
    expect(page).to have_css("h3", text: "Pending and inactive methods", count: 1)
    headings_and_rows = page.all("h3, [data-payment-method-id]").map do |node|
      node["data-payment-method-id"] || node.find("span.block").text
    end
    expect(headings_and_rows).to eq(["2", "Pending and inactive methods", "1"])
  end

  it "preserves removed history and pending provider cleanup" do
    render_methods([method_row(1, "removed", revocation_state: "pending")])
    expect(page).to have_text("Removed locally")
    expect(page).to have_text("No authorized billing payment methods")
    expect(page).to have_css("dd", text: "—")
  end

  it "localizes provider and blockers and renders a truthful empty state" do
    I18n.with_locale(:"zh-CN") do
      render_methods([])
      expect(page).to have_text("尚未保存任何账单付款方式")
      expect(page).to have_button("设置 支付宝（中国）")
      expect(page).not_to have_css(".translation_missing")
    end
  end

  it "links to the provider choices from the header and the empty state" do
    render_methods([method_row(1, "active")])
    within("#billing-payment-methods header") { expect(page).to have_link("Add payment method", href: "#authorize-payment-method") }
    expect(page).to have_css("#authorize-payment-method dialog#add-payment-method-dialog", text: "Add another payment method", visible: :all)
    expect(page).to have_link("Add payment method", visible: true, count: 1)

    render_methods([])
    expect(page).to have_link("Add payment method", href: "#authorize-payment-method", count: 1)
    expect(page).to have_css("#authorize-payment-method", text: "Payment authorization")
  end

  it "discloses pending and inactive methods behind billing-disclosure" do
    render_methods([method_row(1, "active"), method_row(2, "removed")])
    expect(page).to have_css('#inactive-payment-methods[data-controller="billing-disclosure"][data-billing-disclosure-open-value="false"]')
    expect(page).to have_css("#inactive-payment-methods h3", text: "Pending and inactive methods")
    expect(page).to have_css('#inactive-payment-methods [data-payment-method-id="2"]')

    render_methods([method_row(1, "active"), method_row(2, "pending")])
    expect(page).to have_css('#inactive-payment-methods[data-controller="billing-disclosure"][data-billing-disclosure-open-value="true"]')

    render_methods([method_row(1, "active"), method_row(2, "failed")])
    expect(page).to have_css('#inactive-payment-methods[data-controller="billing-disclosure"][data-billing-disclosure-open-value="true"]')
  end

  it "offers no add action when no provider can be set up" do
    render_inline described_class.new(payment_methods: [], available_providers: [], provider_options: [], currency: "CNY", customer_id: 12345678)
    expect(page).not_to have_link("Add payment method")
    expect(page).to have_text("Payment setup unavailable")
  end

  it "reaches older method pages through the wrapper's supplied scoped pagination" do
    render_inline Billing::Admin::PaymentMethodComponent.new(
      payment_methods: [method_row(26, "removed")], available_providers: [], customer_id: 12345678,
      pagination: { page: 2, per_page: 25, total: 51, total_pages: 3 },
      page_path: ->(page) { "/12345678/admin/settings/billing/payment_methods?page=#{page}&locale=zh-CN" }
    )
    expect(page).to have_link(href: "/12345678/admin/settings/billing/payment_methods?page=1&locale=zh-CN")
    expect(page).to have_link(href: "/12345678/admin/settings/billing/payment_methods?page=3&locale=zh-CN")
    expect(page).not_to have_text("No authorized billing payment methods are available.")
  end

  it "uses supplied fixed-currency readiness and does not offer a blocked method as default" do
    render_methods([method_row(1, "active")], payment_method_readiness: {
      1 => { charge_ready: false, default_eligible: false, currency_compatible: false,
             reason_key: "admin_settings.flash.billing.reasons.currency_mismatch" }
    })
    expect(page).to have_text(I18n.t("admin_settings.flash.billing.reasons.currency_mismatch"))
    expect(page).not_to have_button("Make Default")
  end
end
