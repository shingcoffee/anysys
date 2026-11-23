# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::CustomerInvoiceSummaryComponent, type: :component do
  let(:paid) { double(id: 4, to_param: "4", number: "INV-12345678-00004", total_cents: 2900, currency: "USD", paid_at: Time.zone.local(2026, 9, 3)) }

  def render_summary(**summary)
    render_inline described_class.new(customer_id: 12345678, summary: { outstanding: [], unpaid_count: 0, last_paid: nil }.merge(summary))
  end

  it "shows each outstanding currency separately and links to unpaid invoices" do
    render_summary(outstanding: [{ currency: "CNY", total_cents: 19900, count: 1 }, { currency: "USD", total_cents: 3000, count: 2 }], unpaid_count: 3)
    within("[data-summary='outstanding']") do
      expect(page).to have_text("¥199.00 CNY")
      expect(page).to have_text("$30.00 USD")
      expect(page).to have_text("3 unpaid invoices")
      expect(page).to have_link("Review", href: "/12345678/admin/settings/billing/invoices?status=open")
    end
  end

  it "states when nothing is due and no payment exists, without renewal or upsell content" do
    render_summary
    within("[data-summary='outstanding']") { expect(page).to have_text("Nothing due") }
    within("[data-summary='last-payment']") { expect(page).to have_text("No payments recorded yet.") }
    expect(page).to have_css("[data-summary]", count: 2)
    expect(page).not_to have_link("Browse plans")
  end

  it "links the latest payment" do
    render_summary(last_paid: paid)
    within("[data-summary='last-payment']") do
      expect(page).to have_text("$29.00 USD")
      expect(page).to have_link("INV-12345678-00004", href: "/12345678/admin/settings/billing/invoices/4")
    end
  end

  it "renders fully localized in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_summary(last_paid: paid)
      expect(page).not_to have_css(".translation_missing")
    end
  end
end
