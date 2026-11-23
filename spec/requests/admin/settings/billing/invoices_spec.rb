# frozen_string_literal: true

require "rails_helper"

# /:cid/admin/settings/billing/invoices
# Tests: authorization matrix + tenant isolation + index/show/download happy paths.
RSpec.describe "admin/settings/billing/invoices", type: :request do
  let!(:tenant_a) { create(:customer) }
  let!(:admin_a)  { create(:user, :admin, customer: tenant_a) }
  let(:customer)  { tenant_a }
  let(:admin)     { admin_a }

  let!(:tenant_b) { create(:customer) }
  let!(:admin_b)  { create(:user, :admin, customer: tenant_b) }

  let!(:plan_a) { create(:billing_plan) }
  let!(:sub_a)  { create(:billing_subscription, customer: tenant_a, plan: plan_a, currency: "CNY") }

  let!(:plan_b) { create(:billing_plan) }
  let!(:sub_b)  { create(:billing_subscription, customer: tenant_b, plan: plan_b) }

  let!(:invoice_a) do
    create(:billing_invoice, :open, customer: tenant_a, subscription: sub_a, total_cents: 9900, subtotal_cents: 9900, currency: "CNY")
  end

  let!(:invoice_b) do
    create(:billing_invoice, :open, customer: tenant_b, subscription: sub_b)
  end

  # -------------------------------------------------------------------------
  # Authorization
  # -------------------------------------------------------------------------
  describe "GET index auth" do
    let(:guard_path) { admin_settings_billing_invoices_path(tenant_a.id) }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET show auth" do
    let(:guard_path) { admin_settings_billing_invoice_path(tenant_a.id, invoice_a.id) }

    it_behaves_like "an admin-guarded GET"
  end

  describe "GET download auth" do
    let(:guard_path) { download_admin_settings_billing_invoice_path(tenant_a.id, invoice_a.id) }

    it_behaves_like "an admin-guarded GET"
  end

  # -------------------------------------------------------------------------
  # Happy paths for admin of tenant A
  # -------------------------------------------------------------------------
  describe "admin of tenant A" do
    before { sign_in admin_a }

    describe "GET index" do
      it "does not expose tenant B's invoices" do
        get admin_settings_billing_invoices_path(tenant_a.id)
        # Verify the response contains tenant A's invoice number but NOT tenant B's.
        # We use the invoice number (INV-TEST-...) which is unique and long enough to
        # avoid false positives from small integer IDs appearing in page chrome.
        expect(response.body).to include(invoice_a.number)
        expect(response.body).not_to include(invoice_b.number)
      end

      it "paginates at 25 and reaches history beyond 100 rows" do
        100.times do |i|
          create(:billing_invoice, :open, customer: tenant_a, subscription: sub_a,
                 number: "INV-CAP-#{i.to_s.rjust(3, "0")}")
        end

        get admin_settings_billing_invoices_path(tenant_a.id)

        expect(response).to have_http_status(:ok)
        expect(Nokogiri::HTML(response.body).css("tr.table-row").count).to eq(25)
        get admin_settings_billing_invoices_path(tenant_a.id), params: { page: 5 }
        expect(response.body).to include(invoice_a.number)
        expect(response.body).not_to include(invoice_b.number)
      end

      it "ignores a search query and keeps only the status filter on pagination URLs" do
        26.times do |i|
          create(:billing_invoice, :open, customer: tenant_a, subscription: sub_a, number: "LITERAL%_#{i}")
        end
        get admin_settings_billing_invoices_path(tenant_a.id), params: { q: "LITERAL%_", status: "open" }
        document = Nokogiri::HTML(response.body)
        next_link = document.css("a[href]").map { |node| node["href"] }.find { |href| href.include?("page=2") }
        expect(next_link).to be_present
        query = Rack::Utils.parse_nested_query(URI.parse(next_link).query)
        expect(query).to include("status" => "open")
        expect(query).not_to have_key("q")
        get admin_settings_billing_invoices_path(tenant_a.id), params: { q: "LITERAL%_", status: "open", page: 2 }
        expect(response.body).to include(invoice_a.number)
        expect(response.body).not_to include(invoice_b.number)
      end

      it "does not resolve SCA actions or mutate invoices while filtering a list" do
        expect(Billing::InvoicePaymentAction).not_to receive(:for)
        expect(Billing::Activities::CollectInvoice).not_to receive(:call)
        get admin_settings_billing_invoices_path(tenant_a.id), params: { status: "paid", tenant_id: tenant_b.id }
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(invoice_b.number)
      end

      it "summarizes only tenant A's outstanding balance inside the billing tabs" do
        get admin_settings_billing_invoices_path(tenant_a.id)
        document = Nokogiri::HTML(response.body)
        outstanding = document.at_css("[data-summary='outstanding']").text
        expect(outstanding).to include(Billing::CurrencyResolver.format(9900, "CNY"), "1 unpaid invoice")
        expect(outstanding).not_to include("USD")
        expect(document.at_css("[data-billing-tabs] a[aria-current='page']")["href"]).to eq(admin_settings_billing_invoices_path(tenant_a.id))
      end

      it "renders status pills without a search toolbar, and a 2-column summary" do
        get admin_settings_billing_invoices_path(tenant_a.id)
        expect(response).to have_http_status(:ok)
        document = Nokogiri::HTML(response.body)
        pills = document.at_css("nav[aria-label='#{I18n.t("settings_billing.invoices.quick_filters_aria")}']")
        expect(pills).to be_present
        expect(pills.at_css("a[aria-current='true']").text).to include(I18n.t("settings_billing.invoices.all_filter"))
        expect(document.at_css('select[name="status"]')).to be_nil
        expect(document.at_css('input[name="q"]')).to be_nil
        summary = document.at_css("[data-invoice-summary]")
        expect(summary.at_css("[data-summary='outstanding']")).to be_present
        expect(summary.at_css("[data-summary='last-payment']")).to be_present
        expect(summary.css("[data-summary]").size).to eq(2)
      end

      it "discards malformed filters and clamps an out-of-range page without losing tenant scope" do
        get admin_settings_billing_invoices_path(tenant_a.id), params: { status: "forged", page: "999999", tenant_id: tenant_b.id }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(invoice_a.number)
        expect(response.body).not_to include(invoice_b.number)
      end
    end

    it "returns 200 for tenant A's invoice show and download" do
      [
        admin_settings_billing_invoice_path(tenant_a.id, invoice_a.id),
        download_admin_settings_billing_invoice_path(tenant_a.id, invoice_a.id)
      ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
      end
    end

    it "keeps billing tabs on invoice show and omits them from the printable download" do
      get admin_settings_billing_invoice_path(tenant_a.id, invoice_a.id)
      expect(response).to have_http_status(:ok)
      show_document = Nokogiri::HTML(response.body)
      expect(show_document.at_css("[data-billing-tabs] a[aria-current='page']")["href"])
        .to eq(admin_settings_billing_invoices_path(tenant_a.id))

      banner = show_document.at_css("[aria-labelledby='invoice-collection-heading']")
      expect(banner).to be_present
      expect(banner.at_css("header.card-header")).to be_nil
      expect(banner.at_css("[role='status']")).to be_present

      get download_admin_settings_billing_invoice_path(tenant_a.id, invoice_a.id)
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("[data-billing-tabs]")).to be_nil
    end

    it "formats the download total in currency units rather than raw cents" do
      get download_admin_settings_billing_invoice_path(tenant_a.id, invoice_a.id)

      expect(response.body).to include(Billing::CurrencyResolver.format(9900, "CNY"))
      expect(response.body).not_to include("Total: 9900")
    end

    it "never loads a recovery client secret for the printable document" do
      expect(Billing::InvoicePaymentAction).not_to receive(:for)
      get download_admin_settings_billing_invoice_path(tenant_a.id, invoice_a.id)
      expect(response).to have_http_status(:ok)
    end

    it "offers one-time payment on unpaid open and uncollectible invoices" do
      uncollectible = create(:billing_invoice, :open, customer: tenant_a, subscription: sub_a,
                             total_cents: 5000, subtotal_cents: 5000, currency: "CNY")
      uncollectible.update!(status: "uncollectible", collection_state: "exhausted")
      pay_path = admin_settings_billing_invoice_one_time_payment_path(tenant_a.id, invoice_a)
      exhausted_path = admin_settings_billing_invoice_one_time_payment_path(tenant_a.id, uncollectible)

      get admin_settings_billing_invoices_path(tenant_a.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings_billing.invoices.pay_now"))
      expect(response.body).to include(pay_path)
      expect(response.body).to include(exhausted_path)

      get admin_settings_billing_invoice_path(tenant_a.id, invoice_a)
      expect(response.body).to include(pay_path)
      expect(response.body).to include(I18n.t("settings_billing.one_time_payment.action"))

      get admin_settings_billing_invoice_path(tenant_a.id, uncollectible)
      expect(response.body).to include(exhausted_path)
    end

    it "hides one-time payment on paid, void, draft, and download views" do
      paid = create(:billing_invoice, :paid, customer: tenant_a, subscription: sub_a,
                    total_cents: 9900, subtotal_cents: 9900, currency: "CNY", number: "INV-PAID-HIDE")
      voided = create(:billing_invoice, :void, customer: tenant_a, subscription: sub_a,
                      total_cents: 9900, subtotal_cents: 9900, currency: "CNY", number: "INV-VOID-HIDE")
      draft = create(:billing_invoice, customer: tenant_a, subscription: sub_a,
                     total_cents: 9900, subtotal_cents: 9900, currency: "CNY")

      get admin_settings_billing_invoices_path(tenant_a.id)
      expect(response.body).not_to include(admin_settings_billing_invoice_one_time_payment_path(tenant_a.id, paid))
      expect(response.body).not_to include(admin_settings_billing_invoice_one_time_payment_path(tenant_a.id, voided))
      expect(response.body).not_to include(admin_settings_billing_invoice_one_time_payment_path(tenant_a.id, draft))

      get admin_settings_billing_invoice_path(tenant_a.id, paid)
      expect(response.body).not_to include(admin_settings_billing_invoice_one_time_payment_path(tenant_a.id, paid))

      get download_admin_settings_billing_invoice_path(tenant_a.id, invoice_a)
      expect(response.body).not_to include(admin_settings_billing_invoice_one_time_payment_path(tenant_a.id, invoice_a))
      expect(response.body).not_to include(I18n.t("settings_billing.one_time_payment.action"))
    end

    it "localizes the invoice index pay action in zh-CN" do
      get admin_settings_billing_invoices_path(tenant_a.id), params: { locale: "zh-CN" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings_billing.invoices.pay_now", locale: :"zh-CN"))
      expect(response.body).not_to include("translation missing")
    end
  end

  # -------------------------------------------------------------------------
  # Cross-tenant record isolation
  # -------------------------------------------------------------------------
  describe "tenant isolation" do
    before { sign_in admin_a }

    it "blocks admin A from GET index on tenant B's URL" do
      get admin_settings_billing_invoices_path(tenant_b.id)
      expect(response).to have_http_status(:redirect)
      expect(response.location).not_to include("sign_in")
    end

    it "blocks admin A from GET show on tenant B's invoice" do
      # The invoice is scoped to current_customer so the record is not found (404).
      get admin_settings_billing_invoice_path(tenant_a.id, invoice_b.id)
      expect(response).to have_http_status(:not_found)
    end

    it "blocks admin A from GET download on tenant B's invoice" do
      get download_admin_settings_billing_invoice_path(tenant_a.id, invoice_b.id)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "platform owner on a customer settings path" do
    before { sign_in find_or_create_platform_owner }

    it "returns 200 on /81721200/admin/settings/billing/invoices" do
      get admin_settings_billing_invoices_path(find_or_create_platform_owner.customer.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(invoice_a.number, invoice_b.number)
    end

    it "lists only the URL customer's invoices" do
      get admin_settings_billing_invoices_path(tenant_a.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(invoice_a.number)
      expect(response.body).not_to include(invoice_b.number)
    end

    %i[show download].each do |action|
      it "cannot #{action} another customer's invoice through this customer's URL" do
        path = if action == :show
                 admin_settings_billing_invoice_path(tenant_a.id, invoice_b.id)
               else
                 download_admin_settings_billing_invoice_path(tenant_a.id, invoice_b.id)
               end
        get path
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include(invoice_b.number)
      end
    end
  end
end
