# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../services/billing/partition_b_helpers"

# End-to-end request coverage for Settings / Billing one-time payment.
# Activities and the real test DB run; only PSP HTTP is stubbed.
RSpec.describe "admin/settings/billing one-time payment flow", type: :request do
  include BillingPartitionBHelpers

  before { allow_test_root_transaction }
  after { Current.reset }

  def enable_provider(aggregate, provider)
    platform = aggregate.fetch(:platform)
    Payments::PlatformGateway.for_provider(provider).update!(available: true)
    Payments::MerchantAccount.unscoped_by_tenant.find_by(customer_id: platform.id, provider: provider, mode: "sandbox") ||
      create(:payment_merchant_account, provider.to_sym, customer: platform)
  end

  def offer_providers(*keys)
    allow(Billing::OneTimeProviders).to receive(:call) do |currency:|
      keys.map do |key|
        { key: key, label_key: "comp_payments.gateways.#{key}.name",
          supported_currencies: currency.to_s.upcase == "CNY" ? %w[CNY] : %w[USD CNY] }
      end
    end
    allow(Billing::OneTimeProviders).to receive(:options) do |currency:|
      %w[stripe paypal alipay wechat_pay].map do |key|
        compatible = keys.include?(key)
        { key: key, label_key: "comp_payments.gateways.#{key}.name",
          supported_currencies: compatible && currency.to_s.upcase == "CNY" ? %w[CNY] : %w[USD CNY],
          enabled: compatible, currency_compatible: compatible,
          reason_key: compatible ? nil : "settings_billing.payment_methods.currency_incompatible" }
      end
    end
  end

  def stub_charge(payload:, psp_id: "pi_one_time")
    allow(Payments::Gateway).to receive(:charge).and_return(prepay_payload: payload, psp_transaction_id: psp_id)
  end

  def capture_payment!(payment)
    allow(Payments::Activities::Query).to receive(:call) do |**|
      payment.reload.mark_succeeded!(psp_id: payment.psp_transaction_id.presence || "pi_#{payment.id}",
        at: Time.current, notify: { "id" => payment.psp_transaction_id })
      { status: :succeeded }
    end
  end

  def platform_order(invoice)
    Payments::Order.unscoped_by_tenant.find_by!(
      customer_id: Billing::Collector::PLATFORM_OWNER_CUSTOMER_ID,
      external_ref: "billing-inv-#{invoice.id}"
    )
  end

  def expect_no_merchant_secrets(body, accounts)
    accounts.each do |account|
      %i[secret_key client_secret api_key_v3 private_key_pem].each do |key|
        value = account.credential(key)
        next if value.blank? || value.to_s.length < 8

        expect(body).not_to include(value.to_s)
      end
    end
    expect(body).not_to include("-----BEGIN")
  end

  describe "subscription plan → one-time checkout → capture" do
    it "shows the CTA without mutating a draft, then finalizes and settles through confirm" do
      allow(Billing::Onboarding).to receive(:call)
      Billing::Settings.current.update!(collection_mode: "manual", grace_period_days: 14)
      create(:billing_plan, :default_plan)
      platform = ensure_platform_customer
      Payments::PlatformGateway.for_provider("stripe").update!(available: true)
      stripe = Payments::MerchantAccount.unscoped_by_tenant.find_by(customer_id: platform.id, provider: "stripe", mode: "sandbox") ||
        create(:payment_merchant_account, :stripe, customer: platform,
          credentials: { secret_key: "sk_live_merchant_never_leak_abc", publishable_key: "pk_test_x",
                         webhook_signing_secret: "whsec_never_leak" })
      tenant = create(:customer)
      admin = create(:user, :admin, customer: tenant)
      plan = create(:billing_plan, amount_usd: 49, amount_cny: 49)
      request_key = SecureRandom.uuid
      sign_in admin

      patch admin_settings_billing_subscription_path(tenant.id),
            params: { billing_subscription: { plan_code: plan.code, request_key: request_key } }
      expect(response).to have_http_status(:see_other)

      subscription = Billing::Subscription.where(customer_id: tenant.id, request_key: request_key).sole
      draft = subscription.invoices.sole
      expect(subscription.status).to eq("pending")
      expect(draft.status).to eq("draft")

      expect {
        get admin_settings_billing_path(tenant.id)
      }.not_to change { draft.reload.status }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings_billing.one_time_payment.cta"))
      expect(response.body).to include("dialog")
      expect(response.body).to include('name="one_time_payment[provider]"')
      expect(response.body).to include('value="stripe"')
      expect_no_merchant_secrets(response.body, [stripe])

      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
          body: { id: "pi_ot_flow", object: "payment_intent", client_secret: "pi_ot_flow_secret",
                  status: "requires_payment_method", currency: draft.currency.downcase,
                  amount: draft.line_items.where(kind: %w[subscription proration]).sum(:amount_cents),
                  amount_received: 0 }.to_json)

      post admin_settings_billing_subscription_one_time_payment_path(tenant.id),
           params: {
             one_time_payment: {
               provider: "stripe",
               invoice_id: draft.id,
               amount_cents: 1,
               currency: "USD",
               customer_id: create(:customer).id,
               merchant_account_id: 99,
               save_card: true,
               payment_method_id: "pm_forged"
             }
           }
      expect(response).to have_http_status(:see_other)
      expect(draft.reload).to be_open
      expect(response).to redirect_to(admin_settings_billing_invoice_one_time_payment_path(tenant.id, draft))

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("payments--stripe-card")
      expect(response.body).to include("pi_ot_flow_secret")
      expect(response.body).to include("pk_test_x")
      expect(response.body).not_to include("sk_live_merchant_never_leak_abc")
      expect(response.body).not_to include("whsec_never_leak")
      expect(response.headers["Cache-Control"]).to include("no-store")

      order = platform_order(draft)
      expect(order.amount).to eq(BigDecimal(draft.total_cents.to_s) / 100)
      expect(order.currency).to eq(draft.currency)
      attempt = draft.collection_attempts.sole
      expect(attempt).to be_one_time
      expect(attempt.billing_payment_method_id).to be_nil
      expect(attempt.payment.provider).to eq("stripe")
      expect(attempt.payment.attempt_context["save_card"]).to eq(false)
      expect(attempt.payment.attempt_context["billing_one_time"]).to eq(true)

      payment = attempt.payment
      stub_request(:get, %r{\Ahttps://api\.stripe\.com/v1/payment_intents/pi_ot_flow})
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
          body: { id: "pi_ot_flow", object: "payment_intent", status: "succeeded",
                  currency: draft.currency.downcase, amount: draft.total_cents,
                  amount_received: draft.total_cents,
                  latest_charge: { id: "ch_ot_flow", created: Time.current.to_i },
                  metadata: { "out_trade_no" => payment.out_trade_no } }.to_json)

      post confirm_admin_settings_billing_invoice_one_time_payment_path(tenant.id, draft),
           params: { redirect_status: "succeeded", payment_intent: "pi_forged" }
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(admin_settings_billing_invoice_path(tenant.id, draft))
      expect(draft.reload).to be_paid
      expect(subscription.reload.status).to eq("active")
    end
  end

  describe "pending invoice, manual mode, and exhausted recovery" do
    it "lets a tenant admin pay a manual open invoice through create + status" do
      aggregate = billing_aggregate(mode: "manual")
      invoice = aggregate.fetch(:invoice)
      tenant = aggregate.fetch(:tenant)
      sign_in aggregate.fetch(:actor)
      offer_providers("stripe")
      stub_charge(payload: { "client_secret" => "secret_manual_flow" }, psp_id: "pi_manual")

      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: { one_time_payment: { provider: "stripe" } }
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice))
      expect(invoice.reload.effective_collection_mode).to eq("manual")
      expect(invoice.collection_attempts.sole).to be_one_time

      follow_redirect!
      expect(response.body).to include("payments--stripe-card")
      expect(response.body).to include("secret_manual_flow")

      payment = invoice.collection_attempts.sole.payment
      capture_payment!(payment)
      get status_admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice), as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("status" => "succeeded", "invoice_status" => "paid")
      expect(invoice.reload).to be_paid
      expect(aggregate.fetch(:subscription).reload.status).to eq("active")
      expect(response.parsed_body.to_s).not_to include("sk_test_x")
    end

    it "lets a tenant admin pay an exhausted uncollectible invoice through create + confirm" do
      aggregate = billing_aggregate
      invoice = aggregate.fetch(:invoice)
      invoice.update!(status: "uncollectible", collection_state: "exhausted", attempt_count: 4)
      tenant = aggregate.fetch(:tenant)
      sign_in aggregate.fetch(:actor)
      offer_providers("paypal")
      enable_provider(aggregate, "paypal")
      stub_charge(payload: { "paypal_order_id" => "ORDER-UNC" }, psp_id: "paypal_unc")

      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: { one_time_payment: { provider: "paypal" } }
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(response.body).to include("payments--paypal-buttons")
      expect(response.body).to include("ORDER-UNC")
      expect(response.body).not_to include("paypal_oauth")

      payment = invoice.collection_attempts.sole.payment
      capture_payment!(payment)
      post confirm_admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice)
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(admin_settings_billing_invoice_path(tenant.id, invoice))
      expect(invoice.reload).to be_paid
      expect(invoice.attempt_count).to eq(4)
    end
  end

  describe "recurring mandate coexistence" do
    it "does not replace the default recurring method, and the next cycle still auto-charges it" do
      aggregate = billing_aggregate(currency: "CNY")
      invoice = aggregate.fetch(:invoice)
      method = aggregate.fetch(:method)
      method_snapshot = method.attributes
      tenant = aggregate.fetch(:tenant)
      sign_in aggregate.fetch(:actor)
      enable_provider(aggregate, "wechat_pay")
      offer_providers("wechat_pay")
      stub_charge(payload: { "code_url" => "weixin://wxpay/bizpayurl?pr=coexist" }, psp_id: "wx_coexist")

      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: { provider: "wechat_pay" }
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(response.body).to include("payments--qr-poll")

      payment = invoice.collection_attempts.sole.payment
      expect(payment.provider).to eq("wechat_pay")
      Payments::Activities::HandleWebhook.call(
        provider: "wechat_pay",
        signing_account_id: payment.merchant_account_id,
        signing_merchant_id: Payments::MerchantAccount.unscoped_by_tenant.find(payment.merchant_account_id).merchant_id,
        verified_payload: {
          "out_trade_no" => payment.out_trade_no,
          "transaction_id" => "wx_coexist",
          "trade_state" => "SUCCESS",
          "success_time" => Time.current.iso8601,
          "amount" => { "total" => Payments::Money.new(payment.amount, "CNY").smallest_unit, "currency" => "CNY" }
        }
      )

      expect(invoice.reload).to be_paid
      expect(method.reload.attributes.slice("id", "status", "is_default", "payments_subscription_id", "provider"))
        .to eq(method_snapshot.slice("id", "status", "is_default", "payments_subscription_id", "provider"))
      expect(method.is_default).to be(true)
      expect(method).to be_active

      subscription = aggregate.fetch(:subscription).reload
      renewal = Billing::Activities::GenerateInvoice.call(
        subscription: subscription, purpose: "renewal",
        idempotency_key: "renewal:#{subscription.id}",
        period_start: subscription.current_period_end,
        period_end: subscription.current_period_end + 1.month,
        terms_snapshot: invoice.terms_snapshot
      )
      Billing::Activities::FinalizeInvoice.call(invoice: renewal)
      allow(Payments::Gateway).to receive(:charge_subscription).and_return(
        status: :requires_action, psp_transaction_id: "pi_cycle", client_secret: "secret_cycle"
      )
      collected = Billing::Activities::CollectInvoice.call(invoice: renewal)
      expect(collected.status).to eq(:requires_action)
      expect(renewal.collection_attempts.sole.payment_method).to eq(method)
      expect(Payments::Gateway).to have_received(:charge_subscription) do |subscription:, **|
        expect(subscription).to eq(method.payments_subscription)
      end
    end

    it "does not increment dunning when a one-time attempt fails or switches" do
      aggregate = billing_aggregate
      invoice = aggregate.fetch(:invoice)
      tenant = aggregate.fetch(:tenant)
      sign_in aggregate.fetch(:actor)
      offer_providers("stripe", "paypal")
      enable_provider(aggregate, "paypal")
      stub_charge(payload: { "client_secret" => "secret_old_switch" }, psp_id: "pi_old")

      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: { one_time_payment: { provider: "stripe" } }
      expect(invoice.reload.attempt_count).to eq(0)

      allow(Payments::Activities::Query).to receive(:call)
      allow(Payments::Gateway).to receive(:close)
      stub_charge(payload: { "paypal_order_id" => "ORDER-SWITCH" }, psp_id: "paypal_switch")
      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: { one_time_payment: { provider: "paypal" } }

      invoice.reload
      expect(invoice.attempt_count).to eq(0)
      expect(invoice.first_failed_at).to be_nil
      expect(invoice.next_attempt_at).to be_nil
      expect(invoice.collection_attempts.order(:ordinal).first).to have_attributes(state: "failed", failure_code: "provider_switched")
      expect(Billing::Notice.where(kind: "payment_failed", billing_invoice_id: invoice.id)).to be_empty
    end
  end

  describe "provider switching and tampering" do
    it "queries then closes an uncaptured WeChat trade before opening Alipay QR" do
      aggregate = billing_aggregate(currency: "CNY")
      invoice = aggregate.fetch(:invoice)
      tenant = aggregate.fetch(:tenant)
      sign_in aggregate.fetch(:actor)
      enable_provider(aggregate, "wechat_pay")
      enable_provider(aggregate, "alipay")
      offer_providers("wechat_pay", "alipay")
      stub_charge(payload: { "code_url" => "weixin://wxpay/bizpayurl?pr=first" }, psp_id: "wx_first")

      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: { one_time_payment: { provider: "wechat_pay" } }
      wechat_payment = invoice.collection_attempts.sole.payment
      expect(wechat_payment.provider).to eq("wechat_pay")

      queried = false
      allow(Payments::Activities::Query).to receive(:call) do |payment:, **|
        expect(payment.id).to eq(wechat_payment.id)
        queried = true
        { status: :pending }
      end
      allow(Payments::Gateway).to receive(:close) do |payment:, **|
        expect(payment.id).to eq(wechat_payment.id)
        { status: :closed }
      end
      stub_charge(payload: { "qr_code" => "https://qr.alipay.com/bax-switch" }, psp_id: nil)

      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: { one_time_payment: { provider: "alipay" } }
      expect(response).to have_http_status(:see_other)
      expect(queried).to be(true)
      expect(Payments::Gateway).to have_received(:close).once
      expect(invoice.reload.collection_attempts.order(:ordinal).map { |row| [row.payment.provider, row.state, row.failure_code] })
        .to eq([["wechat_pay", "failed", "provider_switched"], ["alipay", "pending", nil]])
      follow_redirect!
      expect(response.body).to include("https://qr.alipay.com/bax-switch").or include("payments--qr-poll")
    end

    it "settles the invoice instead of opening a second charge when the first provider already captured" do
      aggregate = billing_aggregate
      invoice = aggregate.fetch(:invoice)
      tenant = aggregate.fetch(:tenant)
      sign_in aggregate.fetch(:actor)
      offer_providers("stripe", "paypal")
      enable_provider(aggregate, "paypal")
      stub_charge(payload: { "client_secret" => "secret_captured_first" }, psp_id: "pi_captured_first")

      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: { one_time_payment: { provider: "stripe" } }
      payment = invoice.collection_attempts.sole.payment
      capture_payment!(payment)

      expect(Payments::Gateway).to receive(:charge).never
      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: { one_time_payment: { provider: "paypal" } }
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(admin_settings_billing_invoice_path(tenant.id, invoice))
      expect(invoice.reload).to be_paid
      expect(invoice.collection_attempts.where(state: "pending")).to be_empty
      expect(Payments::Payment.unscoped_by_tenant.where(payment_order: platform_order(invoice)).count).to eq(1)
    end

    it "ignores forged money, tenant, account, and save_card fields on POST" do
      aggregate = billing_aggregate
      invoice = aggregate.fetch(:invoice)
      tenant = aggregate.fetch(:tenant)
      other = create(:customer)
      sign_in aggregate.fetch(:actor)
      offer_providers("stripe")
      stub_charge(payload: { "client_secret" => "secret_tamper" }, psp_id: "pi_tamper")

      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: {
             provider: "stripe",
             amount_cents: 1,
             amount: "1.00",
             currency: "EUR",
             customer_id: other.id,
             merchant_account_id: 99,
             payment_method_id: "pm_forged",
             save_card: true
           }
      expect(response).to have_http_status(:see_other)
      order = platform_order(invoice)
      expect(order.amount).to eq(BigDecimal(invoice.total_cents.to_s) / 100)
      expect(order.currency).to eq(invoice.currency)
      expect(order.customer_id).to eq(Billing::Collector::PLATFORM_OWNER_CUSTOMER_ID)
      expect(invoice.collection_attempts.sole.payment.attempt_context["save_card"]).to eq(false)
      expect(Payments::Gateway).to have_received(:charge) do |**kwargs|
        expect(kwargs[:save_card]).to eq(false)
      end
    end

    it "never settles from GET show with a forged redirect_status" do
      aggregate = billing_aggregate
      invoice = aggregate.fetch(:invoice)
      tenant = aggregate.fetch(:tenant)
      sign_in aggregate.fetch(:actor)
      offer_providers("stripe")
      stub_charge(payload: { "client_secret" => "secret_get" }, psp_id: "pi_get")
      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: { one_time_payment: { provider: "stripe" } }

      expect(Payments::Activities::Query).not_to receive(:call)
      get admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
          params: { redirect_status: "succeeded", payment_intent: "pi_forged" }
      expect(response).to have_http_status(:ok)
      expect(invoice.reload).to be_open
      expect(invoice.collection_attempts.sole.state).to eq("pending")
    end
  end

  describe "authorization matrix and locale" do
    def endpoints_for(tenant, invoice)
      [
        [:get, admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice)],
        [:post, admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice)],
        [:get, status_admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice)],
        [:post, confirm_admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice)],
        [:post, admin_settings_billing_subscription_one_time_payment_path(tenant.id)]
      ]
    end

    it "rejects anonymous and member callers on every one-time endpoint without starting a charge" do
      aggregate = billing_aggregate
      invoice = aggregate.fetch(:invoice)
      tenant = aggregate.fetch(:tenant)
      member = create(:user, :member, customer: tenant)
      offer_providers("stripe")

      endpoints_for(tenant, invoice).each do |verb, path|
        expect(Payments::Gateway).not_to receive(:charge)
        public_send(verb, path)
        expect(response).to have_http_status(:found).or have_http_status(:unauthorized)

        sign_in member
        expect(Payments::Gateway).not_to receive(:charge)
        public_send(verb, path)
        expect(response).to have_http_status(:forbidden).or have_http_status(:found).or have_http_status(:not_found)
        sign_out member
      end
      expect(invoice.reload.collection_attempts).to be_empty
    end

    it "forbids a cross-tenant admin and 404s a foreign invoice even for the platform owner" do
      aggregate = billing_aggregate
      invoice = aggregate.fetch(:invoice)
      tenant = aggregate.fetch(:tenant)
      stranger = create(:customer)
      stranger_admin = create(:user, :admin, customer: stranger)
      foreign = create(:billing_invoice, :open, customer: stranger, subscription: create(:billing_subscription, customer: stranger),
                       total_cents: 9900, subtotal_cents: 9900)
      offer_providers("stripe")

      sign_in stranger_admin
      endpoints_for(tenant, invoice).each do |verb, path|
        public_send(verb, path, as: :json)
        expect(response).to have_http_status(:forbidden).or have_http_status(:found)
      end

      sign_out stranger_admin
      sign_in find_or_create_platform_owner
      get admin_settings_billing_invoice_one_time_payment_path(tenant.id, foreign)
      expect(response).to have_http_status(:not_found)
      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, foreign), as: :json
      expect(response).to have_http_status(:not_found).or have_http_status(:forbidden)
      post admin_settings_billing_subscription_one_time_payment_path(tenant.id),
           params: { one_time_payment: { provider: "stripe", invoice_id: foreign.id } }, as: :json
      expect(response).to have_http_status(:not_found).or have_http_status(:forbidden)
    end

    it "renders zh-CN checkout and billing CTA without missing translations" do
      aggregate = billing_aggregate
      invoice = aggregate.fetch(:invoice)
      tenant = aggregate.fetch(:tenant)
      sign_in aggregate.fetch(:actor)
      offer_providers("stripe")
      allow(Billing::AvailableProviders).to receive(:call).and_return(
        [{ key: "stripe", setup_kind: :stripe_setup, supported_currencies: %w[USD CNY] }]
      )
      stub_charge(payload: { "client_secret" => "secret_zh" }, psp_id: "pi_zh")

      get admin_settings_billing_path(tenant.id), params: { locale: "zh-CN" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings_billing.one_time_payment.cta", locale: :"zh-CN"))
      expect(response.body).not_to include("translation missing")
      expect(response.body).not_to include("translation_missing")

      post admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice),
           params: { one_time_payment: { provider: "stripe" }, locale: "zh-CN" }
      expect(response).to have_http_status(:see_other)
      get admin_settings_billing_invoice_one_time_payment_path(tenant.id, invoice), params: { locale: "zh-CN" }
      expect(response.body).to include(I18n.t("settings_billing.one_time_payment.title", locale: :"zh-CN"))
      expect(response.body).not_to include("translation missing")
      expect(response.body).not_to include("translation_missing")
    end
  end
end
