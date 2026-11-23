# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::InvoiceTableComponent, type: :component do
  let(:cny_invoice) do
    instance_double(
      Billing::Invoice,
      id: 1, number: "INV-12345678-001", status: "paid",
      total_cents: 9900, currency: "CNY",
      issued_at: Time.zone.local(2026, 5, 1),
      due_at:    Time.zone.local(2026, 5, 15),
      period_start: nil, period_end: nil,
      customer_id: "12345678",
      customer: nil
    )
  end

  let(:usd_invoice) do
    instance_double(
      Billing::Invoice,
      id: 2, number: "INV-12345678-002", status: "open",
      total_cents: 4950, currency: "USD",
      issued_at: Time.zone.local(2026, 6, 1),
      due_at:    Time.zone.local(2026, 6, 15),
      period_start: nil, period_end: nil,
      customer_id: "12345678",
      customer: nil
    )
  end

  let(:draft_invoice) do
    instance_double(
      Billing::Invoice,
      id: 3, number: nil, status: "draft",
      total_cents: 0, currency: "CNY",
      issued_at: nil, due_at: nil,
      period_start: nil, period_end: nil,
      customer_id: "12345678",
      customer: nil
    )
  end

  def build_stub_helpers(overrides = {})
    double(
      "helpers",
      admin_settings_billing_invoice_path:          "/12345678/admin/settings/billing/invoices/1",
      admin_settings_billing_invoices_path:         "/12345678/admin/settings/billing/invoices",
      admin_settings_billing_subscription_path:     "/12345678/admin/settings/billing/subscription",
      admin_maintenance_platform_billing_invoices_path: "/81721200/admin/maintenance/platform/billing/invoices",
      download_admin_settings_billing_invoice_path: "/12345678/admin/settings/billing/invoices/1/download",
      admin_settings_billing_invoice_one_time_payment_path: "/12345678/admin/settings/billing/invoices/1/one_time_payment",
      admin_maintenance_platform_billing_invoice_path: "/12345678/admin/maintenance/platform/billing/invoices/1",
      protect_against_forgery?: false,
      **overrides
    )
  end

  before do
    allow_any_instance_of(described_class).to receive(:helpers).and_return(build_stub_helpers)
  end

  def build_component(invoices, **opts)
    described_class.new(invoices: invoices, customer_id: "12345678", **opts)
  end

  def render_table(invoices, **opts)
    render_inline(build_component(invoices, **opts))
  end

  # ── Empty state ──────────────────────────────────────────────────────────
  describe "empty state" do
    it "shows 'No invoices yet.' when collection is empty" do
      render_table([])
      expect(page).to have_text("No invoices yet.")
    end
  end

  # ── Localized currency symbols ───────────────────────────────────────────
  describe "currency formatting" do
    it "renders ¥ for a CNY invoice" do
      render_table([cny_invoice])
      expect(page).to have_text("¥99.00")
    end

    it "renders $ for a USD invoice" do
      render_table([usd_invoice])
      expect(page).to have_text("$49.50")
    end

    it "uses the invoice's own currency, not a global one" do
      render_table([cny_invoice, usd_invoice])
      expect(page).to have_text("¥99.00")
      expect(page).to have_text("$49.50")
    end
  end

  # ── Status badge text ────────────────────────────────────────────────────
  describe "status badges" do
    before { render_table([cny_invoice, usd_invoice]) }

    it "renders paid and open status badges" do
      aggregate_failures do
        expect(page).to have_text(I18n.t("comp_billing.invoice_table.statuses.paid"))
        expect(page).to have_text(I18n.t("comp_billing.invoice_table.statuses.open"))
      end
    end
  end

  describe "status_variant mapping" do
    subject(:component) { build_component([]) }

    {
      "draft"         => :default,
      "open"          => :warning,
      "paid"          => :success,
      "void"          => :default,
      "uncollectible" => :danger
    }.each do |status, expected_variant|
      it "maps #{status} → :#{expected_variant}" do
        expect(component.status_variant(status)).to eq(expected_variant)
      end
    end
  end

  # ── Invoice numbers + dates ──────────────────────────────────────────────
  describe "invoice rows" do
    before { render_table([cny_invoice, usd_invoice]) }

    it "renders invoice numbers, issued dates, and due dates" do
      aggregate_failures do
        expect(page).to have_text("INV-12345678-001")
        expect(page).to have_text("INV-12345678-002")
        expect(page).to have_text(I18n.l(Date.new(2026, 5, 1), format: :long))
        expect(page).to have_text(I18n.l(Date.new(2026, 6, 1), format: :long))
        expect(page).to have_text(I18n.l(Date.new(2026, 5, 15), format: :long))
        expect(page).to have_text(I18n.l(Date.new(2026, 6, 15), format: :long))
      end
    end
  end

  # ── Download links ───────────────────────────────────────────────────────
  # The template renders both a mobile card list and a desktop table, so each
  # invoice produces two View links and two Download links (one per layout).
  describe "download links" do
    it "renders a Download link per invoice (×2 layouts = ×4 total for 2 invoices)" do
      render_table([cny_invoice, usd_invoice])
      expect(page).to have_link("Download", count: 4)
    end

    it "renders a View link per invoice (×2 layouts = ×4 total for 2 invoices)" do
      render_table([cny_invoice, usd_invoice])
      expect(page).to have_link("View", count: 4)
    end

    it "renders at least one Download link for a single invoice" do
      render_table([cny_invoice])
      expect(page).to have_link("Download")
    end
  end

  # ── Draft invoice without a number ──────────────────────────────────────
  describe "draft invoice" do
    it "shows (draft) when number is nil" do
      render_table([draft_invoice])
      expect(page).to have_text("(draft)")
    end
  end

  # ── context: :platform — adds Customer column ────────────────────────────
  describe "platform context" do
    before { render_table([cny_invoice], context: :platform) }

    it "includes Customer column header and shows customer_id in rows" do
      aggregate_failures do
        expect(page).to have_css("th", text: "Customer")
        expect(page).to have_text("12345678")
      end
    end

    it "builds Download using the invoice tenant, not the platform page customer" do
      foreign = instance_double(
        Billing::Invoice,
        id: 9, number: "INV-55555555-001", status: "paid",
        total_cents: 100, currency: "USD",
        issued_at: Time.zone.local(2026, 5, 1),
        due_at: Time.zone.local(2026, 5, 15),
        customer_id: "55555555",
        customer: nil
      )
      helpers = build_stub_helpers
      allow(helpers).to receive(:download_admin_settings_billing_invoice_path)
        .with("55555555", foreign)
        .and_return("/55555555/admin/settings/billing/invoices/9/download")
      allow_any_instance_of(described_class).to receive(:helpers).and_return(helpers)

      component = described_class.new(invoices: [foreign], customer_id: "81721200", context: :platform)
      expect(component.download_path(foreign)).to eq("/55555555/admin/settings/billing/invoices/9/download")
    end
  end

  describe "settings context (default)" do
    it "does not render Customer column" do
      render_table([cny_invoice])
      expect(page).not_to have_css("th", text: "Customer")
    end
  end

  describe "#status_label" do
    subject(:component) { build_component([]) }

    it "falls back to the raw key for an unknown status" do
      expect(component.status_label("unknown")).to eq("unknown")
    end
  end

  it "localizes status in zh-CN" do
    I18n.with_locale(:"zh-CN") do
      render_table([cny_invoice])
      expect(page).to have_text(I18n.t("comp_billing.invoice_table.statuses.paid"))
    end
  end

  describe "customer settings presentation" do
    it "keeps dates, currencies, statuses and customer-scoped actions in both layouts" do
      render_table([cny_invoice, usd_invoice, draft_invoice], context: :settings, customer_settings: true)
      expect(page).to have_link("View", count: 6)
      expect(page).to have_link("Download", count: 6)
      expect(page).to have_text("¥99.00")
      expect(page).to have_text("$49.50")
      expect(page).to have_text("(draft)")
      expect(page).to have_css('[role=region][tabindex="0"] table')
      expect(page).to have_css(".card")
      expect(page).not_to have_css("th", text: "Customer")
      expect(page).not_to have_css("a[href*='/maintenance/platform/']")
    end

    it "shows one neutral empty state shared by both layouts" do
      render_table([], customer_settings: true)
      expect(page).to have_text("No invoices yet.", count: 1)
      expect(page).not_to have_css("table")
      expect(page).not_to have_css("form")
      expect(page).not_to have_link("Download")
      expect(page).not_to have_link("Reset")
      expect(page).to have_text("Invoices appear here once your subscription is billed.")
      expect(page).not_to have_link("Browse plans")
      expect(page).not_to have_text("0 invoices")
    end

    it "emphasizes unpaid invoices and links each number to its detail page" do
      render_table([cny_invoice, usd_invoice], customer_settings: true)
      expect(page).to have_css("table a.btn-primary", text: "View", count: 1)
      expect(page).to have_css("table th[scope=row] a", text: "INV-12345678-002")
    end

    it "offers a filter reset from a filtered empty state" do
      render_table([], customer_settings: true, filters: { status: "void" })
      expect(page).to have_text("No billing records match these filters.")
      expect(page).to have_text("Try a different status.")
      expect(page).to have_link("Reset", href: "/12345678/admin/settings/billing/invoices", class: "btn-sm")
    end

    it "filters only by status pills, with no search toolbar" do
      render_table([cny_invoice], customer_settings: true)
      expect(page).to have_css("nav[aria-label='Filter invoices by status']")
      expect(page).not_to have_field("Search invoice numbers")
      expect(page).not_to have_field("Status")
      expect(page).not_to have_field("tenant_id")
    end

    it "keeps the Status select on the platform and module compact toolbar" do
      render_table([cny_invoice])
      expect(page.find_field("Status").all("option").first.text).to eq("All statuses")
    end

    it "does not override explicit platform context" do
      render_table([cny_invoice], customer_settings: true, context: :platform)
      expect(page).to have_css("th", text: "Customer")
      expect(page).to have_css("a[href*='/maintenance/platform/']")
    end
  end

  it "renders canonical collection state in mobile and desktop without exposing a secret" do
    render_table([usd_invoice], collection_by_invoice_id: { 2 => { state: "requires_action", client_secret: "never-in-list" } })
    expect(page).to have_text("Payment authentication required", count: 2)
    expect(page.native.to_s).not_to include("never-in-list")
    expect(page).to have_css("table caption", visible: :all)
  end

  %w[pending requires_action reconciliation_required manual blocked exhausted stopped].each do |state|
    it "preserves #{state} collection on an uncollectible invoice in both layouts" do
      allow(usd_invoice).to receive(:status).and_return("uncollectible")
      render_table([usd_invoice], collection_by_invoice_id: { usd_invoice.id => { state: state } })
      expect(page).to have_css("table tbody td", text: I18n.t("comp_billing.invoice_table.statuses.uncollectible"), count: 1)
      expect(page).to have_css("ul.lg\\:hidden li", text: I18n.t("comp_billing.invoice_table.statuses.uncollectible"), count: 1)
      expect(page).to have_text(I18n.t("comp_billing.collection.states.#{state}"), count: 2)
      expect(page).not_to have_text(I18n.t("comp_billing.collection.states.exhausted")) unless state == "exhausted"
    end
  end

  it "retains literal filters, resets search pagination and uses the supplied owner-scoped page callable" do
    render_table([], context: :platform, filters: { q: "INV_%", status: "open", tenant_id: "55555555" },
      pagination: { page: 2, per_page: 25, total: 126, total_pages: 6 },
      page_path: ->(page) { "/81721200/admin/maintenance/platform/billing/invoices?tenant_id=55555555&page=#{page}" })
    expect(page).to have_field("q", with: "INV_%")
    expect(page).to have_field("tenant_id", with: "55555555")
    expect(page).to have_text("No billing records match these filters.")
    expect(page).to have_link(href: /81721200.*page=3/)
    expect(page).not_to have_css('form input[name="page"]')
  end

  it "keeps subscription invoice filters and pagination fixed to the subscription detail" do
    component = build_component([], context: :platform, history_url: "/81721200/admin/maintenance/platform/billing/subscriptions/8",
      filters: { q: "older", tenant_id: "55555555", status: "paid" })
    render_inline component
    expect(page).not_to have_field("tenant_id")
    expect(component.pagination_path.call(2)).to include("subscriptions/8?")
    expect(component.pagination_path.call(2)).not_to include("tenant_id")
  end
end
