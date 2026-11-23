# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::CustomerInvoiceTableComponent, type: :component do
  def render_table(**opts)
    render_inline described_class.new(invoices: [], customer_id: "12345678", **opts)
  end

  def pill_query(label)
    href = page.find("nav[aria-label='Filter invoices by status'] a", text: /\A#{Regexp.escape(label)}\z/)[:href]
    Rack::Utils.parse_nested_query(URI.parse(href).query)
  end

  it "marks the active status pill and links each pill to its status alone" do
    render_table(filters: { q: "INV_%", status: "open" })
    within("nav[aria-label='Filter invoices by status']") do
      expect(page).to have_css("a[aria-current='true']", text: /\AOpen\z/)
      expect(page).to have_link("All")
      expect(page).to have_link("Paid")
      expect(page).to have_link("Uncollectible")
      expect(page).to have_link("Void")
    end
    expect(pill_query("All")).to eq({})
    expect(pill_query("Open")).to eq("status" => "open")
    expect(pill_query("Paid")).to eq("status" => "paid")
    expect(pill_query("Uncollectible")).to eq("status" => "uncollectible")
    expect(pill_query("Void")).to eq("status" => "void")
  end

  it "marks All current and treats a stray search query as unfiltered" do
    render_table(filters: { q: "INV-1" })
    within("nav[aria-label='Filter invoices by status']") do
      expect(page).to have_css("a[aria-current='true']", text: /\AAll\z/)
    end
    expect(page).to have_text("No invoices yet.")
    expect(page).not_to have_link("Reset")
  end

  it "renders no search toolbar or total count" do
    render_table(pagination: { page: 1, per_page: 25, total: 3, total_pages: 1 })
    expect(page).not_to have_css("form")
    expect(page).not_to have_text("3 invoices")
  end

  def invoice_row(id:, status:, number: "INV-#{id}")
    double("invoice", id: id, to_param: id.to_s, number: number, status: status,
      total_cents: 4950, currency: "USD", issued_at: Time.zone.local(2026, 6, 1),
      due_at: Time.zone.local(2026, 6, 15), period_start: nil, period_end: nil,
      customer_id: "12345678", customer: nil)
  end

  it "keeps View primary on an unpaid invoice that cannot take a one-time payment" do
    open_invoice = invoice_row(id: 2, status: "open")
    render_table(invoices: [open_invoice])
    expect(page).to have_css("table a.btn-primary", text: "View")
    expect(page).not_to have_link("Pay now")
  end

  it "offers Pay now and demotes View when the collection fact allows one-time payment" do
    open_invoice = invoice_row(id: 2, status: "open")
    paid_invoice = invoice_row(id: 1, status: "paid", number: "INV-1")
    render_table(invoices: [paid_invoice, open_invoice], collection_by_invoice_id: { 2 => { can_pay_one_time: true } })
    expect(page).to have_link("Pay now", href: "/12345678/admin/settings/billing/invoices/2/one_time_payment", count: 2)
    expect(page).to have_css("table a.btn-primary", text: "Pay now")
    expect(page).to have_css("table a.btn-secondary", text: "View", count: 1)
    expect(page).to have_css("table a.btn-ghost", text: "View", count: 1)
    expect(page).to have_css("ul.lg\\:hidden a.btn-primary", text: "Pay now")
    expect(page).not_to have_css("form", text: "Pay now")
    expect(page).to have_link(href: "/12345678/admin/settings/billing/invoices/2/download", title: "Download", count: 2)
  end

  it "offers Pay now on uncollectible invoices and hides it for void and draft rows" do
    uncollectible = invoice_row(id: 4, status: "uncollectible", number: "INV-4")
    voided = invoice_row(id: 5, status: "void", number: "INV-5")
    draft = invoice_row(id: 6, status: "draft", number: nil)
    render_table(
      invoices: [uncollectible, voided, draft],
      collection_by_invoice_id: { 4 => { can_pay_one_time: true }, 5 => { can_pay_one_time: false }, 6 => { can_pay_one_time: false } }
    )
    expect(page).to have_link("Pay now", href: "/12345678/admin/settings/billing/invoices/4/one_time_payment", count: 2)
    expect(page).not_to have_link("Pay now", href: "/12345678/admin/settings/billing/invoices/5/one_time_payment")
    expect(page).not_to have_link("Pay now", href: "/12345678/admin/settings/billing/invoices/6/one_time_payment")
    expect(page).to have_css("table a.btn-ghost", text: "View", count: 2)
  end

  it "shows collection notes only on unpaid rows" do
    open_invoice = invoice_row(id: 2, status: "open")
    paid_invoice = invoice_row(id: 1, status: "paid", number: "INV-1")
    voided = invoice_row(id: 5, status: "void", number: "INV-5")
    render_table(
      invoices: [open_invoice, paid_invoice, voided],
      filters: { status: "open" },
      collection_by_invoice_id: { 2 => { state: "requires_action" } }
    )
    expect(page).to have_text("Payment authentication required", count: 2)
    expect(page).not_to have_text(I18n.t("comp_billing.collection.states.settled"))
    expect(page).not_to have_text(I18n.t("comp_billing.collection.states.stopped"))
    expect(page).to have_css("nav[aria-label='Filter invoices by status'] a[aria-current='true']", text: /\AOpen\z/)
  end
end

