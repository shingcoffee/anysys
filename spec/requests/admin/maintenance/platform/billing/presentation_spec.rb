# frozen_string_literal: true

require "rails_helper"

RSpec.describe "platform billing presentation facts", type: :request do
  include_context "as platform owner"
  let(:tenant) { create(:customer) }
  let!(:subscription) { create(:billing_subscription, customer: tenant, currency: "CNY") }
  let(:invoice) { create(:billing_invoice, :open, customer: tenant, subscription: subscription, currency: "CNY", total_cents: 1500) }
  let(:path) { admin_maintenance_platform_billing_invoice_path(customer.id, invoice) }

  def capture_presentation(controller)
    allow_any_instance_of(controller).to receive(:render).and_wrap_original do |original, *args, **kwargs|
      @presented = %i[collection filters pending_changes pending_plan_change can_cancel_immediately coupon_benefit
                      collection_by_invoice_id invoices].to_h do |key|
        [key, original.receiver.instance_variable_get("@#{key}")]
      end
      original.call(*args, **kwargs)
    end
  end

  def inflight_attempt(state)
    method = create(:billing_payment_method, customer: tenant, provider: "stripe")
    order = create(:payment_order, customer: customer, external_ref: "billing-inv-#{invoice.id}", currency: "CNY")
    payment = create(:payment, customer: customer, payment_order: order, provider: "stripe", status: "pending")
    Billing::CollectionAttempt.create!(customer: tenant, invoice: invoice, payment: payment, payment_method: method,
      merchant_account: method.merchant_account, ordinal: 1, request_key: payment.out_trade_no, state: state)
  end

  it "exposes manual settlement and void/authorization forms using the saved mode rather than current global settings" do
    invoice.update!(collection_override_mode: "manual")
    Billing::Settings.current.update!(collection_mode: "gateway")
    capture_presentation(Admin::Maintenance::Platform::Billing::InvoicesController)
    get path, params: { q: "INV%_", status: "open", tenant_id: tenant.id }
    expect(response).to have_http_status(:ok)
    expect(@presented[:collection]).to include(state: "manual", effective_mode: "manual", recorded_mode: "gateway",
      can_retry: false, can_mark_paid: true, can_void: true, can_authorize_collection: true)
    expect(@presented[:filters]).to eq(q: "INV%_", status: "open", tenant_id: tenant.id.to_s)
    expect(response.body).to include(mark_paid_admin_maintenance_platform_billing_invoice_path(customer.id, invoice),
                                     void_admin_maintenance_platform_billing_invoice_path(customer.id, invoice),
                                     'name="settlement[reference]"', 'name="collection[mode]"')
  end

  it "shows a saved retry timestamp and functional recovery instead of hiding it behind nil collection facts" do
    invoice.update!(collection_state: "retry_wait", next_attempt_at: 1.day.from_now)
    method = create(:billing_payment_method, :active, customer: tenant, provider: "stripe")
    allow(Billing::Providers).to receive(:readiness_reason).with(payment_method: method, invoice: invoice).and_return(nil)
    capture_presentation(Admin::Maintenance::Platform::Billing::InvoicesController)
    get path
    expect(@presented[:collection]).to include(state: "retry_wait", next_attempt_at: invoice.next_attempt_at, can_retry: true)
    expect(response.body).to include(retry_admin_maintenance_platform_billing_invoice_path(customer.id, invoice))
  end

  it "allows intentional exhausted-debt recovery within the saved deadline" do
    invoice.update!(status: "uncollectible", collection_state: "exhausted", next_attempt_at: nil)
    method = create(:billing_payment_method, :active, customer: tenant, provider: "stripe")
    allow(Billing::Providers).to receive(:readiness_reason).with(payment_method: method, invoice: invoice).and_return(nil)
    capture_presentation(Admin::Maintenance::Platform::Billing::InvoicesController)
    get path
    expect(@presented[:collection]).to include(state: "exhausted", can_retry: true, can_mark_paid: true, can_void: true)
    expect(response.body).to include(retry_admin_maintenance_platform_billing_invoice_path(customer.id, invoice))
  end

  it "uses the shared accepted request lifetime for a zero-grace initial invoice" do
    subscription.update!(status: "pending", current_period_start: 1.hour.ago)
    terms = subscription.plan_snapshot.merge("collection_mode" => "gateway", "grace_period_days" => 0,
                                             "tax_rate_bps" => 0, "dunning_schedule" => [])
    initial = create(:billing_invoice, :open, customer: tenant, subscription: subscription, currency: "CNY",
      purpose: "initial", period_start: subscription.current_period_start, period_end: subscription.current_period_end,
      due_at: subscription.current_period_start, terms_snapshot: terms, total_cents: 1500)
    method = create(:billing_payment_method, :active, customer: tenant, provider: "stripe")
    allow(Billing::Providers).to receive(:readiness_reason).with(payment_method: method, invoice: initial).and_return(nil)
    capture_presentation(Admin::Maintenance::Platform::Billing::InvoicesController)
    get admin_maintenance_platform_billing_invoice_path(customer.id, initial)
    expect(response).to have_http_status(:ok)
    expect(@presented[:collection]).to include(state: "ready", can_retry: true,
                                             deadline: Billing::PlanChangePolicy.request_deadline(initial))
    expect(@presented[:collection][:deadline]).to eq(initial.period_end)
    expect(Billing::PlanChangePolicy.grace_deadline(initial)).to be < Time.current
    expect(initial.reload.status).to eq("open")
  end

  it "keeps requires-action collection unresolved and disables every conflicting owner mutation" do
    inflight_attempt("requires_action")
    expect(Billing::InvoicePaymentAction).not_to receive(:for)
    capture_presentation(Admin::Maintenance::Platform::Billing::InvoicesController)
    get path
    expect(@presented[:collection]).to include(state: "requires_action", unresolved: true, can_retry: false,
      can_mark_paid: false, can_void: false, can_authorize_collection: false, next_attempt_at: nil)
    expect(response.body).not_to include('name="settlement[reference]"', 'name="collection[mode]"')
  end

  it "projects an uncredited real capture as reconciliation-required rather than ready for another payment" do
    order = create(:payment_order, customer: customer, external_ref: "billing-inv-#{invoice.id}", currency: "CNY")
    create(:payment, customer: customer, payment_order: order, status: "succeeded", paid_at: Time.current)
    capture_presentation(Admin::Maintenance::Platform::Billing::InvoicesController)
    get path
    expect(@presented[:collection]).to include(state: "reconciliation_required", unresolved: true,
      can_retry: false, can_mark_paid: false, can_void: false, can_authorize_collection: false)
  end

  it "retains genuine expired debt for manual reconciliation but prohibits a new gateway attempt" do
    invoice.update_columns(due_at: 20.days.ago)
    capture_presentation(Admin::Maintenance::Platform::Billing::InvoicesController)
    get path
    expect(@presented[:collection]).to include(state: "stopped", can_retry: false, can_mark_paid: true,
                                             can_void: true, next_attempt_at: nil)
    expect(invoice.reload.status).to eq("open")
  end

  it "does not silently relabel an invoice whose frozen currency differs from its subscription" do
    subscription.update!(currency: "USD")
    capture_presentation(Admin::Maintenance::Platform::Billing::InvoicesController)
    get path
    expect(@presented[:collection]).to include(state: "unavailable", reason: :currency_mismatch,
                                             can_retry: false, can_authorize_collection: false)
  end

  it "keeps collection facts and operator input on a rejected override" do
    invoice.update!(collection_override_mode: "manual")
    allow(Billing::Activities::AuthorizeInvoiceCollection).to receive(:call).and_return(
      Billing::Result.new(status: :invalid, reason: :invalid_collection_authorization)
    )
    expect(Billing::Activities::CollectInvoice).not_to receive(:call)
    capture_presentation(Admin::Maintenance::Platform::Billing::InvoicesController)
    post retry_admin_maintenance_platform_billing_invoice_path(customer.id, invoice),
         params: { collection: { mode: "gateway", note: "Retain this submitted note" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(@presented[:collection]).to include(state: "manual", effective_mode: "manual", mode: "gateway",
      note: "Retain this submitted note", can_mark_paid: true, can_authorize_collection: true)
    expect(response.body).to include("Retain this submitted note")
  end

  it "retains the manual settlement form and facts after a rejected reference" do
    allow(Billing::Activities::MarkInvoicePaid).to receive(:call).and_return(
      Billing::Result.new(status: :invalid, reason: :settlement_reference_required)
    )
    capture_presentation(Admin::Maintenance::Platform::Billing::InvoicesController)
    post mark_paid_admin_maintenance_platform_billing_invoice_path(customer.id, invoice),
         params: { settlement: { reference: "", note: "Keep settlement note" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(@presented[:collection][:can_mark_paid]).to be(true)
    expect(response.body).to include('name="settlement[reference]"', "Keep settlement note")
  end

  it "uses explicit owner cancellation eligibility and pending-change facts on list and detail" do
    change = Billing::PlanChange.create!(customer: tenant, subscription: subscription, from_plan: subscription.plan,
      to_plan: create(:billing_plan), request_key: SecureRandom.uuid, kind: "scheduled", status: "scheduled",
      effective_at: subscription.current_period_end, period_start: subscription.current_period_start,
      period_end: subscription.current_period_end, from_snapshot: subscription.plan_snapshot,
      target_snapshot: subscription.plan_snapshot)
    capture_presentation(Admin::Maintenance::Platform::Billing::SubscriptionsController)
    get admin_maintenance_platform_billing_subscriptions_path(customer.id), params: { tenant_id: tenant.id }
    expect(@presented[:pending_changes]).to eq(subscription.id => change)
    get admin_maintenance_platform_billing_subscription_path(customer.id, subscription)
    expect(@presented[:can_cancel_immediately]).to be(true)
    expect(@presented[:pending_plan_change]).to eq(change)
    expect(response.body).to include(admin_maintenance_platform_billing_subscription_cancellation_path(customer.id, subscription))
    subscription.update!(status: "cancelled", ended_at: Time.current)
    get admin_maintenance_platform_billing_subscription_path(customer.id, subscription)
    expect(@presented[:can_cancel_immediately]).to be(false)
  end
end
