# frozen_string_literal: true

require "rails_helper"

RSpec.describe "tenant billing presentation facts", type: :request do
  include_context "as admin"
  let!(:subscription) { create(:billing_subscription, customer: customer, currency: "CNY") }
  let(:subscription_path) { admin_settings_billing_subscription_path(customer.id) }
  let(:invoice_path) { admin_settings_billing_invoice_path(customer.id, invoice) }
  let(:invoice) { create(:billing_invoice, :open, customer: customer, subscription: subscription, currency: "CNY", total_cents: 1500) }

  def capture_presentation(controller)
    allow_any_instance_of(controller).to receive(:render).and_wrap_original do |original, *args, **kwargs|
      @presented = %i[plan_review request_key form usage coupon_benefit recovery subscription_actions collection filters
                      payment_method_readiness provider_options authorization_action confirmation_url].to_h do |key|
        [key, original.receiver.instance_variable_get("@#{key}")]
      end
      original.call(*args, **kwargs)
    end
  end

  it "renders an HTML review using the same authoritative preview as JSON without creating an invoice" do
    target = create(:billing_plan, amount_cny: 200)
    key = SecureRandom.uuid
    preview = { kind: :immediate, effective_at: Time.current, currency: "CNY", subtotal_cents: 1234,
                tax_cents: 56, total_cents: 1290, allowed: true, reason: nil }
    expect(Billing::PlanChangePolicy).to receive(:preview).with(subscription: subscription, new_plan: target).and_return(preview)
    expect(Billing::Activities::ChangePlan).not_to receive(:call)
    expect(Billing::Activities::FinalizeInvoice).not_to receive(:call)
    capture_presentation(Admin::Settings::Billing::SubscriptionsController)

    expect {
      get plan_change_preview_admin_settings_billing_subscription_path(customer.id),
          params: { plan_code: target.code, request_key: key, total_cents: 1, currency: "USD" }
    }.not_to change(Billing::Invoice, :count)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(@presented[:plan_review]).to include(preview.merge(plan: target, plan_code: target.code, interval: target.interval))
    expect(@presented[:plan_review][:calculated_at]).to be_present
    expect(@presented[:request_key]).to eq(key)
    expect(response.body).to include('name="billing_subscription[request_key]"', "value=\"#{key}\"")
  end

  it "returns the subscription screen with 422 for an unavailable HTML review target" do
    expect(Billing::PlanChangePolicy).not_to receive(:preview)
    get plan_change_preview_admin_settings_billing_subscription_path(customer.id), params: { plan_code: "MISSING" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include(I18n.t("settings_navigation.items.plan_subscription"))
  end

  it "retains the selected review, submitted UUID and actual Reform form after a failed change" do
    target = create(:billing_plan, amount_cny: 200)
    key = SecureRandom.uuid
    form = Billing::Contracts::ChangePlan.new(OpenStruct.new(plan_code: target.code, request_key: key))
    form.errors.add(:base, I18n.t("admin_settings.flash.billing.reasons.validation_failed"))
    allow(Billing::Activities::ChangePlan).to receive(:call).and_return(
      Billing::Result.new(status: :invalid, form: form, errors: form.errors.messages)
    )
    capture_presentation(Admin::Settings::Billing::SubscriptionsController)
    patch subscription_path, params: { billing_subscription: { plan_code: target.code, request_key: key } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(@presented[:form]).to equal(form)
    expect(@presented[:request_key]).to eq(key)
    expect(@presented[:plan_review][:plan]).to eq(target)
    expect(response.body).to include("value=\"#{key}\"")
  end

  it "uses the outstanding model request identity when reopening the subscription screen" do
    change = Billing::PlanChange.create!(customer: customer, subscription: subscription, from_plan: subscription.plan,
      to_plan: create(:billing_plan), request_key: SecureRandom.uuid, kind: "scheduled", status: "scheduled",
      effective_at: subscription.current_period_end, period_start: subscription.current_period_start,
      period_end: subscription.current_period_end, from_snapshot: subscription.plan_snapshot,
      target_snapshot: subscription.plan_snapshot)
    capture_presentation(Admin::Settings::Billing::SubscriptionsController)
    get subscription_path
    expect(response).to have_http_status(:ok)
    expect(@presented[:request_key]).to eq(change.request_key)
  end

  it "provides cancellation/resume bounds without adding a recovery warning to a healthy subscription" do
    capture_presentation(Admin::Settings::Billing::SubscriptionsController)
    get subscription_path
    expect(@presented[:subscription_actions]).to eq(can_cancel: true, can_resume: false)
    expect(@presented[:recovery]).to be_nil
    subscription.update!(cancel_at_period_end: true, current_period_end: 1.day.ago)
    get subscription_path
    expect(@presented[:subscription_actions]).to eq(can_cancel: false, can_resume: false)
  end

  it "loads real tenant page/entity/member-role usage even when the actor is the platform owner" do
    baseline_quota = Billing::Quota.for(customer)
    baseline = %w[page entity member].to_h { |key| [key, baseline_quota.usage(key)] }
    entity = create(:entity, customer: customer)
    create(:page, customer: customer, entity: entity)
    create(:user, :member, customer: customer)
    create(:user, :admin, customer: customer)
    create(:user, :member, customer: create(:customer))
    sign_in find_or_create_platform_owner
    expect(Billing::Quota).to receive(:for).with(customer).and_call_original
    capture_presentation(Admin::Settings::Billing::SubscriptionsController)
    get subscription_path
    expect(response).to have_http_status(:ok)
    expect(@presented[:usage]).to eq(baseline.transform_values { |value| value + 1 })
  end

  context "with accepted coupon terms" do
    let!(:coupon) { create(:billing_coupon, :repeating, percent_off: 20) }
    let!(:redemption) do
      Billing::CouponRedemption.create!(customer: customer, subscription: subscription, coupon: coupon,
        redeemed_at: 2.days.ago, cycles_used: 1,
        terms_snapshot: coupon.attributes.slice(*Billing::Activities::ApplyCoupon::TERMS))
    end

    it "uses accepted terms and redemption cycles after catalog archive and unrelated invoices" do
      coupon.update!(active: false, archived_at: Time.current, name: "Changed catalog name", percent_off: 50)
      subscription.update!(billing_coupon_id: coupon.id)
      create(:billing_invoice, :void, customer: customer, subscription: subscription)
      capture_presentation(Admin::Settings::Billing::SubscriptionsController)
      expect(Billing::Discounts).not_to receive(:reserve_for_invoice!)
      get subscription_path
      expect(response).to have_http_status(:ok)
      expect(@presented[:coupon_benefit]).to include(percent_off: 20, remaining_cycles: 2, cycles_used: 1, eligible: true)
      expect(@presented[:coupon_benefit][:name]).to eq(redemption.terms_snapshot.fetch("name"))
    end

    it "keeps a free cycle from being presented as coupon-eligible or consuming allowance" do
      subscription.update!(amount_cents: 0, plan_snapshot: subscription.plan_snapshot.merge("amount_cents" => 0))
      capture_presentation(Admin::Settings::Billing::SubscriptionsController)
      get subscription_path
      expect(@presented[:coupon_benefit]).to include(eligible: false, reason: :free_cycle, remaining_cycles: 2)
      expect(redemption.reload.cycles_used).to eq(1)
    end

    it "uses an accepted scheduled target when determining the next billed cycle" do
      subscription.update!(amount_cents: 0, plan_snapshot: subscription.plan_snapshot.merge("amount_cents" => 0))
      target = create(:billing_plan)
      Billing::PlanChange.create!(customer: customer, subscription: subscription, from_plan: subscription.plan,
        to_plan: target, request_key: SecureRandom.uuid, kind: "scheduled", status: "scheduled",
        effective_at: subscription.current_period_end, period_start: subscription.current_period_start,
        period_end: subscription.current_period_end, from_snapshot: subscription.plan_snapshot,
        target_snapshot: subscription.plan_snapshot.merge("amount_cents" => 1500))
      capture_presentation(Admin::Settings::Billing::SubscriptionsController)
      get subscription_path
      expect(@presented[:coupon_benefit]).to include(eligible: true, remaining_cycles: 2)
    end
  end

  it "provides only the purchasing tenant's debt links and the saved access deadline" do
    subscription.update!(status: "past_due", current_period_end: 1.day.ago)
    debt = create(:billing_invoice, :open, customer: customer, subscription: subscription, currency: "CNY",
      period_start: subscription.current_period_end, due_at: 1.day.ago,
      terms_snapshot: { "collection_mode" => "manual", "currency" => "CNY", "grace_period_days" => 3 })
    foreign = create(:billing_invoice, :open, customer: create(:customer))
    capture_presentation(Admin::Settings::Billing::SubscriptionsController)
    get subscription_path
    expect(@presented[:recovery][:invoices]).to include(debt)
    expect(@presented[:recovery][:invoices]).not_to include(foreign)
    expect(@presented[:recovery][:grace_deadline]).to eq(Billing::PlanChangePolicy.access_deadline(subscription))
    expect(@presented[:recovery][:can_resume]).to be(false)
  end

  it "supplies a functional tenant invoice recovery action and validated detail filters" do
    invoice.update!(collection_override_mode: "gateway")
    method = create(:billing_payment_method, :active, customer: customer, provider: "stripe")
    allow(Billing::Providers).to receive(:readiness_reason).with(payment_method: method, invoice: invoice).and_return(nil)
    capture_presentation(Admin::Settings::Billing::InvoicesController)
    get invoice_path, params: { q: "INV%_", status: "open", tenant_id: create(:customer).id }
    expect(response).to have_http_status(:ok)
    expect(@presented[:collection]).to include(state: "ready", effective_mode: "gateway", can_retry: true,
                                             can_mark_paid: false, can_void: false, can_authorize_collection: false)
    expect(@presented[:filters]).to eq(q: "INV%_", status: "open")
    expect(response.body).to include(admin_settings_billing_invoice_payment_path(customer.id, invoice))
  end

  it "does not invent a collection policy or enable retry for a broken issued snapshot" do
    invoice.update_columns(terms_snapshot: {})
    capture_presentation(Admin::Settings::Billing::InvoicesController)
    get invoice_path
    expect(response).to have_http_status(:ok)
    expect(@presented[:collection]).to include(state: "unavailable", effective_mode: nil, deadline: nil,
                                             reason: :invoice_policy_invalid, policy_valid: false, can_retry: false)
  end

  it "exposes only the exact pending invoice's Stripe authentication action and scoped return path" do
    method = create(:billing_payment_method, customer: customer, provider: "stripe")
    account = method.merchant_account
    account.write_credentials(secret_key: "sk_only_server", publishable_key: "pk_public_billing")
    account.save!
    platform = ensure_platform_customer
    order = create(:payment_order, customer: platform, external_ref: "billing-inv-#{invoice.id}", currency: "CNY", amount: 15)
    payment = create(:payment, customer: platform, payment_order: order, provider: "stripe", flow: "card",
      amount: 15, status: "pending", prepay_payload: {
        "_attempt" => { "merchant_account_id" => account.id },
        "requires_action" => true, "client_secret" => "pi_exact_invoice_secret"
      })
    Billing::CollectionAttempt.create!(customer: customer, invoice: invoice, payment: payment, payment_method: method,
      merchant_account: account, ordinal: 1, request_key: payment.out_trade_no, state: "requires_action")
    capture_presentation(Admin::Settings::Billing::InvoicesController)
    get invoice_path
    expect(response).to have_http_status(:ok)
    expect(@presented[:collection]).to include(state: "requires_action", can_retry: false, unresolved: true)
    expect(response.body).to include("pi_exact_invoice_secret", invoice_path)
    expect(response.body).not_to include("sk_only_server")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "stops new collection after the saved deadline while retaining the debt" do
    invoice.update_columns(due_at: 20.days.ago)
    capture_presentation(Admin::Settings::Billing::InvoicesController)
    get invoice_path
    expect(@presented[:collection]).to include(state: "stopped", reason: :request_expired,
                                             can_retry: false, next_attempt_at: nil)
    expect(invoice.reload.status).to eq("open")
  end
end
