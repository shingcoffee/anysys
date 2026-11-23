# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::CustomerBillingPageComponent, type: :component do
  def render_page(active, locale: :en)
    I18n.with_locale(locale) do
      with_request_url("/12345678/admin/settings/billing/subscription") do
        render_inline(described_class.new(customer_id: 12345678, active: active, description: "Billing copy")) { "Body" }
      end
    end
  end

  it "titles the page from the active tab and links every billing section" do
    render_page(:payment_methods)
    expect(page).to have_css("h1", text: "Payment methods")
    expect(page).to have_text("Billing copy")
    within("nav[aria-label='Billing sections']") do
      expect(page).to have_link("Plan", href: "/12345678/admin/settings/billing/subscription")
      expect(page).to have_link("Payment methods", href: "/12345678/admin/settings/billing/payment_methods")
      expect(page).to have_link("Invoices", href: "/12345678/admin/settings/billing/invoices")
      expect(page).to have_css("a[aria-current='page']", count: 1, text: "Payment methods")
    end
    expect(page).to have_text("Body")
  end

  it "translates tab labels" do
    render_page(:invoices, locale: :"zh-CN")
    expect(page).to have_css("nav[aria-label='账单分区'] a[aria-current='page']", text: I18n.t("settings_navigation.items.invoices", locale: :"zh-CN"))
    expect(page).not_to have_css(".translation_missing")
  end

  it "rejects an unknown section" do
    expect { described_class.new(customer_id: 1, active: :usage) }.to raise_error(ArgumentError)
  end

  it "renders positive tab counts and omits zero or missing badges" do
    with_request_url("/12345678/admin/settings/billing/invoices") do
      render_inline described_class.new(customer_id: 12345678, active: :invoices, description: "Billing copy",
        tab_counts: { payment_methods: 2, invoices: 3 })
    end
    expect(page).to have_css('[data-tab-count="payment_methods"]', text: "2")
    expect(page).to have_css('[data-tab-count="invoices"]', text: "3")
    expect(page).not_to have_css('[data-tab-count="plan"]')

    with_request_url("/12345678/admin/settings/billing/invoices") do
      render_inline described_class.new(customer_id: 12345678, active: :invoices,
        tab_counts: { payment_methods: 0, invoices: nil })
    end
    expect(page).not_to have_css("[data-tab-count]")
  end

  it "uses a subpage title, breadcrumbs and actions while keeping print-hidden tabs" do
    with_request_url("/12345678/admin/settings/billing/invoices/19") do
      render_inline described_class.new(
        customer_id: 12345678, active: :invoices, title: "Invoice INV-19", description: "Invoice copy",
        breadcrumbs: [
          { label: "Invoices", path: "/12345678/admin/settings/billing/invoices" },
          { label: "INV-19" }
        ],
        actions: [{ label: "Back to invoices", path: "/12345678/admin/settings/billing/invoices", class: "print:hidden" }]
      ).with_content("Invoice body")
    end
    expect(page).to have_css("h1", text: "Invoice INV-19")
    expect(page).to have_link("Invoices", href: "/12345678/admin/settings/billing/invoices")
    expect(page).to have_text("INV-19")
    expect(page).to have_link("Back to invoices", href: "/12345678/admin/settings/billing/invoices")
    expect(page).to have_css("nav[data-billing-tabs].print\\:hidden")
    expect(page).to have_css("nav[data-billing-tabs] a[aria-current='page']", text: "Invoices")
    expect(page).to have_text("Invoice body")
  end

  it "constrains the frame and uses underline tabs" do
    render_page(:plan)
    expect(page).to have_css("div.mx-auto.max-w-5xl", text: "Body")
    expect(page).to have_css("nav[data-billing-tabs] ul.border-b.border-border-subtle")
    current = page.find("nav[data-billing-tabs] a[aria-current='page']")
    expect(current[:class]).to include("text-text-primary", "after:bg-accent")
    idle = page.find("nav[data-billing-tabs] a", text: "Payment methods")
    expect(idle[:class]).to include("text-text-secondary", "hover:text-text-primary")
    expect(idle[:class]).not_to include("after:bg-accent")
  end

  it "keeps settings_billing English and Simplified Chinese keys and interpolation variables in parity" do
    flatten = lambda do |value, prefix = nil|
      case value
      when Hash
        value.flat_map { |key, item| flatten.call(item, [prefix, key].compact.join(".")) }
      else
        [[prefix, value.to_s.scan(/%\{(\w+)\}/).flatten.sort]]
      end
    end
    english = YAML.safe_load_file(Rails.root.join("config/locales/settings_billing.en.yml")).fetch("en")
    chinese = YAML.safe_load_file(Rails.root.join("config/locales/settings_billing.zh-CN.yml")).fetch("zh-CN")
    expect(flatten.call(chinese).to_h).to eq(flatten.call(english).to_h)
  end
end
