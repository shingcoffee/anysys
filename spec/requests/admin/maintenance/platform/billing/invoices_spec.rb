# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/maintenance/platform/billing/invoices", type: :request do
  let!(:platform_owner) { find_or_create_platform_owner }
  let(:platform_cid) { platform_owner.customer_id }
  let!(:tenant) { create(:customer) }
  let!(:subscription) { create(:billing_subscription, customer: tenant) }
  let!(:invoice) { create(:billing_invoice, :open, customer: tenant, subscription: subscription) }
  let(:path) { admin_maintenance_platform_billing_invoice_path(platform_cid, invoice) }
  let(:guard_path) { admin_maintenance_platform_billing_invoices_path(platform_cid) }

  it_behaves_like "a platform-owner-guarded GET"

  %i[mark_paid void retry].each do |action|
    describe "#{action} authorization" do
      let(:guard_path) { public_send("#{action}_admin_maintenance_platform_billing_invoice_path", platform_cid, invoice) }
      it_behaves_like "a platform-owner-guarded request", :post
    end
  end

  describe "owner requests" do
    before { sign_in platform_owner }

    it "requires the owner platform URL even for an owner switching tenant context" do
      expect(Billing::Activities::MarkInvoicePaid).not_to receive(:call)
      post mark_paid_admin_maintenance_platform_billing_invoice_path(tenant.id, invoice),
           params: { settlement: { reference: "bank-1" } }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "rejects the tenant-prefixed platform read while admitting the authenticated owner's canonical read" do
      get path
      expect(response).to have_http_status(:ok)
      get admin_maintenance_platform_billing_invoice_path(tenant.id, invoice), as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(invoice.number)
    end

    it "passes manual provenance and the authenticated actor without client financial attributes" do
      expect(Billing::Activities::MarkInvoicePaid).to receive(:call).with(
        invoice: invoice, source: :manual, actor: platform_owner, reference: "bank-2026-1", note: "Verified transfer"
      ).and_return(Billing::Result.new(status: :paid, invoice: invoice))
      post mark_paid_admin_maintenance_platform_billing_invoice_path(platform_cid, invoice), params: {
        source: "zero", actor: create(:user, :admin, customer: tenant).id, payment_id: 123, amount_cents: 1,
        settlement: { reference: "bank-2026-1", note: "Verified transfer", paid_at: "2000-01-01", currency: "USD" }
      }
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(path)
    end

    it "renders a missing manual reference as 422 without marking the invoice paid" do
      allow(Billing::Activities::MarkInvoicePaid).to receive(:call).and_return(
        Billing::Result.new(status: :invalid, reason: :settlement_reference_required)
      )
      post mark_paid_admin_maintenance_platform_billing_invoice_path(platform_cid, invoice)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(invoice.reload.status).to eq("open")
      expect(flash[:notice]).to be_nil
    end

    it "reports settlement review rather than claiming service recovery" do
      allow(Billing::Activities::MarkInvoicePaid).to receive(:call).and_return(
        Billing::Result.new(status: :review_required, invoice: invoice)
      )
      post mark_paid_admin_maintenance_platform_billing_invoice_path(platform_cid, invoice),
           params: { settlement: { reference: "late-capture" } }
      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to eq(I18n.t("maint_platform.flash.billing.invoice_settlement_review"))
      expect(flash[:notice]).to be_nil
    end

    it "retains an in-flight void refusal as 409" do
      expect(Billing::Activities::VoidInvoice).to receive(:call).with(invoice: invoice).and_return(
        Billing::Result.new(status: :conflict, reason: :collection_in_flight)
      )
      post void_admin_maintenance_platform_billing_invoice_path(platform_cid, invoice)
      expect(response).to have_http_status(:conflict)
      expect(flash[:notice]).to be_nil
      expect(invoice.reload.status).to eq("open")
    end

    it "retries with the recovery trigger and preserves issued collection mode when no override is requested" do
      expect(Billing::Activities::AuthorizeInvoiceCollection).not_to receive(:call)
      expect(Billing::Activities::CollectInvoice).to receive(:call).with(invoice: invoice, trigger: :recovery)
        .and_return(Billing::Result.new(status: :pending_manual))
      post retry_admin_maintenance_platform_billing_invoice_path(platform_cid, invoice)
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq(I18n.t("admin_settings.flash.billing.collection.pending_manual"))
    end

    it "authorizes an explicit owner override before recovery" do
      expect(Billing::Activities::AuthorizeInvoiceCollection).to receive(:call).with(
        invoice: invoice, actor: platform_owner, mode: "gateway", note: "Collect outstanding debt"
      ).ordered.and_return(Billing::Result.new(status: :authorized))
      expect(Billing::Activities::CollectInvoice).to receive(:call).with(invoice: invoice, trigger: :recovery)
        .ordered.and_return(Billing::Result.new(status: :pending))
      post retry_admin_maintenance_platform_billing_invoice_path(platform_cid, invoice),
           params: { collection: { mode: "gateway", note: "Collect outstanding debt", amount_cents: 1 } }
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq(I18n.t("admin_settings.flash.billing.collection.pending"))
    end

    it "does not collect after a rejected override" do
      allow(Billing::Activities::AuthorizeInvoiceCollection).to receive(:call).and_return(
        Billing::Result.new(status: :blocked, reason: :collection_in_flight)
      )
      expect(Billing::Activities::CollectInvoice).not_to receive(:call)
      post retry_admin_maintenance_platform_billing_invoice_path(platform_cid, invoice),
           params: { collection: { mode: "gateway", note: "Override" } }
      expect(response).to have_http_status(:conflict)
    end

    %i[blocked exhausted skipped].each do |status|
      it "returns 409 rather than generic success for #{status} recovery" do
        allow(Billing::Activities::CollectInvoice).to receive(:call).and_return(Billing::Result.new(status: status))
        post retry_admin_maintenance_platform_billing_invoice_path(platform_cid, invoice)
        expect(response).to have_http_status(:conflict)
        expect(flash[:notice]).to be_nil
      end
    end

    it "filters across tenants without replacing the owner's route customer" do
      other = create(:customer)
      foreign = create(:billing_invoice, :open, customer: other, subscription: create(:billing_subscription, customer: other))
      get admin_maintenance_platform_billing_invoices_path(platform_cid), params: { tenant_id: tenant.id, status: "open" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(invoice.number)
      expect(response.body).not_to include(foreign.number)
    end

    it "paginates history beyond 100 with 25 rows per page" do
      100.times do |i|
        create(:billing_invoice, :open, customer: tenant, subscription: subscription, number: "PLATFORM-HISTORY-#{i}")
      end
      get admin_maintenance_platform_billing_invoices_path(platform_cid), params: { tenant_id: tenant.id }
      expect(Nokogiri::HTML(response.body).css("tr.table-row").count).to eq(25)
      get admin_maintenance_platform_billing_invoices_path(platform_cid), params: { tenant_id: tenant.id, page: 5 }
      expect(response.body).to include(invoice.number)
    end

    it "never resolves tenant SCA secrets on a platform list or detail" do
      expect(Billing::InvoicePaymentAction).not_to receive(:for)
      get admin_maintenance_platform_billing_invoices_path(platform_cid)
      get path
      expect(response).to have_http_status(:ok)
    end
  end
end
