# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::InvoiceDetailComponent, type: :component do
  let(:line_item_sub) do
    instance_double(
      Billing::InvoiceLineItem,
      description: "Pro Monthly subscription",
      kind: "subscription", quantity: 1,
      unit_amount_cents: 9900, amount_cents: 9900
    )
  end

  let(:line_item_discount) do
    instance_double(
      Billing::InvoiceLineItem,
      description: "Coupon SAVE10", kind: "discount",
      quantity: 1, unit_amount_cents: -990, amount_cents: -990
    )
  end

  let(:line_item_tax) do
    instance_double(
      Billing::InvoiceLineItem,
      description: "Tax (6%)", kind: "tax",
      quantity: 1, unit_amount_cents: 534, amount_cents: 534
    )
  end

  let(:invoice) do
    instance_double(
      Billing::Invoice,
      id: 1, number: "INV-12345678-001", status: "paid",
      currency: "CNY",
      subtotal_cents:  9900,
      discount_cents:  990,
      tax_cents:       534,
      total_cents:     9444,
      period_start:    Time.zone.local(2026, 5, 1),
      period_end:      Time.zone.local(2026, 6, 1),
      issued_at:       Time.zone.local(2026, 5, 1, 10, 0),
      due_at:          Time.zone.local(2026, 5, 1),
      paid_at:         Time.zone.local(2026, 5, 2, 8, 30),
      attempt_count:   1,
      errors: Billing::Invoice.new.errors,
      collection_mode: "gateway",
      settlement_review_code: nil,
      customer: nil,
      customer_id:     "12345678",
      line_items:      [line_item_sub, line_item_discount, line_item_tax]
    )
  end

  before do
    stub_helpers = double(
      "helpers",
      mark_paid_admin_maintenance_platform_billing_invoice_path: "/cid/billing/invoices/1/mark_paid",
      admin_settings_billing_invoice_path: "/12345678/admin/settings/billing/invoices/1",
      admin_maintenance_platform_billing_invoice_path: "/81721200/admin/maintenance/platform/billing/invoices/1",
      admin_settings_billing_payment_methods_path: "/12345678/admin/settings/billing/payment_methods",
      admin_settings_billing_invoice_payment_path: "/12345678/admin/settings/billing/invoices/1/payment",
      void_admin_maintenance_platform_billing_invoice_path:      "/cid/billing/invoices/1/void",
      retry_admin_maintenance_platform_billing_invoice_path:     "/cid/billing/invoices/1/retry",
      download_admin_settings_billing_invoice_path: "/12345678/admin/settings/billing/invoices/1/download",
      admin_settings_billing_invoice_one_time_payment_path: "/12345678/admin/settings/billing/invoices/1/one_time_payment",
      protect_against_forgery?: false
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  def build_component(invoice: self.invoice, **opts)
    described_class.new(invoice: invoice, customer_id: "12345678", **opts)
  end

  def render_detail(**opts)
    render_inline(build_component(**opts))
  end

  describe "invoice header" do
    before { render_detail }

    it "renders invoice number, status badge, issued date, and print button" do
      aggregate_failures do
        expect(page).to have_text("INV-12345678-001")
        expect(page).to have_text(I18n.t("comp_billing.invoice_table.statuses.paid"))
        expect(page).to have_text(I18n.l(Date.new(2026, 5, 1), format: :long))
        expect(page).to have_button("Print")
      end
    end

    it "localizes invoice dates in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        render_detail
        expect(page).to have_text(I18n.l(Date.new(2026, 5, 1), format: :long))
        expect(page).to have_text(I18n.l(Time.zone.local(2026, 5, 2, 8, 30), format: :short))
        expect(page).to have_text(I18n.t("comp_billing.invoice_table.statuses.paid"))
      end
    end
  end

  describe "data-controller attribute" do
    it "sets billing-invoice Stimulus controller on root" do
      render_detail
      expect(page).to have_css("[data-controller='billing-invoice']")
    end
  end

  describe "line items" do
    before { render_detail }

    it "renders all line item descriptions and kind labels" do
      aggregate_failures do
        expect(page).to have_text("Pro Monthly subscription")
        expect(page).to have_text("Coupon SAVE10")
        expect(page).to have_text("Tax (6%)")
        expect(page).to have_text(I18n.t("comp_billing.invoice_detail.kinds.subscription"))
        expect(page).to have_text(I18n.t("comp_billing.invoice_detail.kinds.discount"))
        expect(page).to have_text(I18n.t("comp_billing.invoice_detail.kinds.tax"))
      end
    end
  end

  describe "totals section" do
    before { render_detail }

    it "renders subtotal, discount, tax, and total amounts" do
      aggregate_failures do
        expect(page).to have_text("Subtotal")
        expect(page).to have_text("¥99.00")
        expect(page).to have_text("Discount")
        expect(page).to have_text("¥9.90")
        expect(page).to have_text("Tax")
        expect(page).to have_text("¥5.34")
        expect(page).to have_text("Total")
        expect(page).to have_text("¥94.44")
      end
    end
  end

  describe "platform mode admin actions" do
    let(:open_invoice) do
      instance_double(
        Billing::Invoice,
        id: 2, number: "INV-99-001", status: "open",
        currency: "CNY", subtotal_cents: 9900, discount_cents: 0, tax_cents: 0,
        total_cents: 9900, period_start: nil, period_end: nil,
        issued_at: nil, due_at: nil, paid_at: nil,
        attempt_count: 0, customer_id: "99", customer: nil, collection_mode: "manual", errors: Billing::Invoice.new.errors,
        line_items: []
      )
    end

    it "renders mark_paid and retry and void buttons for open invoice in platform mode" do
      render_detail(invoice: open_invoice, platform: true, collection: { can_mark_paid: true, can_retry: true, can_void: true })
      expect(page).to have_button("Mark as Paid")
      expect(page).to have_button("Retry Collection")
      expect(page).to have_button("Void Invoice")
      expect(page).to have_text("Operator actions")
      expect(page).to have_text("Danger zone")
    end

    it "does not render admin action buttons in non-platform mode" do
      render_detail(invoice: open_invoice, platform: false)
      expect(page).not_to have_button("Mark as Paid")
      expect(page).not_to have_button("Void Invoice")
    end

    it "does not render admin actions for a paid invoice even in platform mode" do
      render_detail(platform: true)
      expect(page).not_to have_button("Mark as Paid")
      expect(page).not_to have_button("Retry Collection")
    end
  end

  describe "customer_id shown in platform mode" do
    it "displays customer_id in the header dl" do
      render_detail(platform: true)
      expect(page).to have_css("dt", text: "Customer")
      expect(page).to have_css("dd", text: "12345678")
    end
  end

  describe "format_amount" do
    subject(:component) { build_component }

    it "formats positive, negative, and zero amounts correctly" do
      aggregate_failures do
        expect(component.format_amount(9900)).to eq("¥99.00 CNY")
        expect(component.format_amount(-990)).to eq("-¥9.90 CNY")
        expect(component.format_amount(0)).to eq("¥0.00 CNY")
      end
    end
  end

  describe "#status_label" do
    it "falls back to the raw key for an unknown status" do
      unknown = instance_double(Billing::Invoice, status: "unknown")
      expect(build_component(invoice: unknown).status_label).to eq("unknown")
    end
  end

  describe "#kind_label" do
    it "falls back to the raw key for an unknown kind" do
      expect(build_component.kind_label("fee")).to eq("fee")
    end
  end

  describe "customer settings presentation" do
    %w[draft open paid void uncollectible].each do |status|
      it "shows #{status} without exposing platform collection operations" do
        allow(invoice).to receive(:status).and_return(status)
        render_detail(customer_settings: true, platform: false)
        expect(page).to have_text(I18n.t("comp_billing.invoice_table.statuses.#{status}"))
        expect(page).not_to have_css("form")
      end
    end

    it "renders mobile line item details and a full print table with all totals" do
      render_detail(customer_settings: true)
      expect(page).to have_css("dl", text: "Qty")
      expect(page).to have_css("table", text: "Coupon SAVE10")
      expect(page).to have_text("-¥9.90")
      expect(page).to have_text("¥94.44")
      expect(page).to have_text("Billing period")
      expect(page).to have_text("Due date")
      expect(page).to have_text("Paid at")
      expect(page).to have_link("Download", href: "/12345678/admin/settings/billing/invoices/1/download")
      expect(page).to have_css('button[data-action="billing-invoice#print"]')
      expect(page).to have_css(".card")
      expect(page).not_to have_button("Mark as Paid")
      expect(page).not_to have_button("Retry Collection")
      expect(page).not_to have_button("Void Invoice")
    end

    it "uses the same full content for the HTML download without a self-link" do
      render_detail(customer_settings: true, download: true)
      expect(page).to have_text("Pro Monthly subscription")
      expect(page).to have_text("Coupon SAVE10")
      expect(page).to have_text("Tax (6%)")
      expect(page).to have_text("¥94.44")
      expect(page).to have_button("Print")
      expect(page).not_to have_link("Download")
    end

    it "keeps explicit platform actions even if the presentation flag is accidentally supplied" do
      allow(invoice).to receive(:status).and_return("open")
      render_detail(customer_settings: true, platform: true, collection: { can_mark_paid: true, can_retry: true, can_void: true })
      expect(page).to have_button("Mark as Paid")
      expect(page).to have_button("Retry Collection")
      expect(page).to have_button("Void Invoice")
      expect(page).not_to have_link("Download")
    end

    it "handles a draft without dates or line items in both responsive layouts" do
      allow(invoice).to receive_messages(number: nil, status: "draft", line_items: [], period_start: nil, period_end: nil,
                                         issued_at: nil, due_at: nil, paid_at: nil, discount_cents: 0, tax_cents: 0)
      render_detail(customer_settings: true, download: true)
      expect(page).to have_text("(draft)")
      expect(page).to have_text("No line items.", count: 2)
      expect(page).to have_css("dd", text: "—", count: 3)
      expect(page).not_to have_text("Discount")
      expect(page).not_to have_text("Tax")
    end

    it "leads the customer document with the invoice total and a toned collection state" do
      allow(invoice).to receive(:status).and_return("open")
      render_detail(customer_settings: true, collection: { state: "requires_action", effective_mode: "gateway" })
      expect(page).to have_css("p.text-title", text: "¥94.44")
      within("[aria-labelledby='invoice-collection-heading']") do
        expect(page).to have_css(".bg-warning-subtle svg")
        expect(page).to have_css("[role='status']", text: "Payment authentication required")
        expect(page).to have_link("Payment methods", href: "/12345678/admin/settings/billing/payment_methods")
      end
    end

    it "localizes the customer document" do
      I18n.with_locale(:"zh-CN") do
        render_detail(customer_settings: true, download: true)
        expect(page).to have_text(I18n.t("comp_billing.invoice_detail.billing_period"))
        expect(page).to have_text(I18n.t("comp_billing.invoice_table.statuses.paid"))
        expect(page).not_to have_css(".translation_missing")
      end
    end
  end

  it "keeps requires-action recovery on the original tenant payment and omits secrets from download" do
    allow(invoice).to receive(:status).and_return("open")
    action = { kind: :stripe_sca, publishable_key: "pk_test", client_secret: "pi_exact_secret" }
    render_detail(customer_settings: true, collection: { state: "requires_action", can_retry: false }, payment_action: action)
    expect(page).to have_css('[data-payments--stripe-card-client-secret-value="pi_exact_secret"]')
    expect(page).to have_button("Complete payment authentication")
    expect(page).not_to have_button("Pay invoice")
    render_detail(customer_settings: true, download: true, collection: { state: "requires_action", can_retry: true }, payment_action: action)
    expect(page).not_to have_css('[data-controller="payments--stripe-card"], form')
    expect(page.native.to_s).not_to include("pi_exact_secret")
  end

  it "records manual settlement with required reference and preserves rejected operator input" do
    allow(invoice).to receive(:status).and_return("open")
    render_detail(platform: true, collection: { state: "manual", can_mark_paid: true }, settlement: { reference: "bank-9", note: "Checked receipt" })
    expect(page).to have_field("settlement[reference]", with: "bank-9")
    expect(page).to have_css('input[name="settlement[reference]"][required]')
    expect(page).to have_field("settlement[note]", with: "Checked receipt")
    expect(page).to have_text("does not charge a payment provider")
  end

  it "gives terminal invoice state precedence over stale action descriptors" do
    render_detail(platform: true, collection: { state: "ready", can_retry: true, can_mark_paid: true, can_void: true })
    expect(page).to have_text("Settled")
    expect(page).not_to have_button("Retry Collection")
    expect(page).not_to have_button("Mark as Paid")
    expect(page).not_to have_button("Void Invoice")
  end

  %w[pending requires_action reconciliation_required].each do |state|
    it "keeps uncollectible #{state} visible and prevents a second collection" do
      allow(invoice).to receive(:status).and_return("uncollectible")
      render_detail(platform: true, collection: { state: state, can_retry: true, can_mark_paid: false, can_void: false })
      expect(page).to have_text(I18n.t("comp_billing.collection.states.#{state}"))
      expect(page).not_to have_text(I18n.t("comp_billing.invoice_detail.collection_exhausted"))
      expect(page).not_to have_button("Retry Collection")
      expect(page).not_to have_button("Mark as Paid")
      expect(page).not_to have_button("Void Invoice")
    end
  end

  it "allows authentication of the exact pending payment on an uncollectible tenant invoice" do
    allow(invoice).to receive(:status).and_return("uncollectible")
    action = { kind: :stripe_sca, publishable_key: "pk_test", client_secret: "pi_recovery_secret" }
    render_detail(customer_settings: true, collection: { state: "requires_action", can_retry: false }, payment_action: action)
    expect(page).to have_button("Complete payment authentication")
    expect(page).to have_css('[data-payments--stripe-card-client-secret-value="pi_recovery_secret"]')
    expect(page).not_to have_button("Pay invoice")
    expect(page).not_to have_text(I18n.t("comp_billing.invoice_detail.collection_exhausted"))
  end

  it "allows voiding uncollectible debt only when the owner eligibility flag permits it" do
    allow(invoice).to receive(:status).and_return("uncollectible")
    render_detail(platform: true, collection: { state: "exhausted", can_void: true })
    expect(page).to have_button("Void Invoice")
    render_detail(platform: true, collection: { state: "exhausted", can_void: false })
    expect(page).not_to have_button("Void Invoice")
  end

  it "links to one-time payment on an unpaid customer invoice" do
    allow(invoice).to receive_messages(status: "open", id: 1)
    render_detail(customer_settings: true, collection: { can_pay_one_time: true, state: "ready" })
    expect(page).to have_link("One-time payment", href: "/12345678/admin/settings/billing/invoices/1/one_time_payment")
  end

  it "links to one-time payment on an exhausted uncollectible customer invoice" do
    allow(invoice).to receive_messages(status: "uncollectible", id: 1)
    render_detail(customer_settings: true, collection: { can_pay_one_time: true, state: "exhausted" })
    expect(page).to have_link("One-time payment", href: "/12345678/admin/settings/billing/invoices/1/one_time_payment")
  end

  it "hides one-time payment on paid, void, draft, and download views" do
    allow(invoice).to receive(:status).and_return("paid")
    render_detail(customer_settings: true, collection: { can_pay_one_time: true, state: "settled" })
    expect(page).not_to have_link("One-time payment")

    allow(invoice).to receive(:status).and_return("void")
    render_detail(customer_settings: true, collection: { can_pay_one_time: true, state: "stopped" })
    expect(page).not_to have_link("One-time payment")

    allow(invoice).to receive(:status).and_return("draft")
    render_detail(customer_settings: true, collection: { can_pay_one_time: true, state: "draft" })
    expect(page).not_to have_link("One-time payment")

    allow(invoice).to receive(:status).and_return("open")
    render_detail(customer_settings: true, download: true, collection: { can_pay_one_time: true, state: "ready" })
    expect(page).not_to have_link("One-time payment")
  end

  it "offers an explicit collection-mode override only on authorized owner detail" do
    allow(invoice).to receive(:status).and_return("open")
    render_detail(platform: true, collection: { state: "manual", effective_mode: "manual", can_authorize_collection: true })
    expect(page).to have_select("collection[mode]", selected: "Manual")
    expect(page).to have_css('textarea[name="collection[note]"][required]')
    render_detail(platform: false, collection: { state: "manual", can_authorize_collection: true })
    expect(page).not_to have_select("collection[mode]")
  end
end
