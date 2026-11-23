# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Payments::Checkouts", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:payment_module) { enable_module!("payment", customer, name: "Payments") }

  before do
    Current.customer = customer
    make_eligible("alipay")
    allow(Payments::Gateway).to receive(:charge).and_return(prepay_payload: { qr_code: "Q" })
  end

  let(:checkout_path) { "/#{customer.id}/payments/checkout" }

  # Orders are always created server-side; tests build them directly. `ref`
  # is positional (bare-string) so no keyword-swallowing gotcha applies.
  def create_order(ref, amount: 1.00, subject: "s", **extra)
    create(:payment_order, external_ref: ref, amount: amount, subject: subject, **extra)
  end

  # Makes a provider eligible for this customer: platform-available + an
  # active MerchantAccount with all declared credentials populated.
  def make_eligible(provider)
    Payments::PlatformGateway.for_provider(provider).update!(available: true)
    create(:payment_merchant_account, provider.to_sym, customer: customer,
           merchant_id: "M-#{provider}")
  end

  # Orders are created server-side (e.g. by subscription cron); the public
  # checkout never trusts amount/subject/body from the request because
  # those came from an unauthenticated visitor.
  it "renders the checkout page for an existing order" do
    create_order("r1")
    get checkout_path, params: { ref: "r1" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Order #r1")
    expect(response.body).to include('value="alipay"')
  end

  it "renders the checkout as a full storefront HTML page for a Turbo-driven visit" do
    create_order("r-turbo")
    get checkout_path, params: { ref: "r-turbo" },
        headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
    expect(response.body).to include("<html").and include("Order #r-turbo")
  end

  it "returns 400 with a translated message when ref is missing" do
    get checkout_path
    expect(response).to have_http_status(:bad_request)
    expect(response.body).to eq(I18n.t("comp_payments.flash.missing_ref"))
  end

  it "returns 404 with a translated message when the order does not exist" do
    get checkout_path, params: { ref: "no-such-order" }
    expect(response).to have_http_status(:not_found)
    expect(response.body).to eq(I18n.t("comp_payments.flash.order_not_found"))
  end

  it "renders checkout for an Alipay in-app browser that Rails :modern would 406" do
    create_order("r-alipay-ua")
    get checkout_path, params: { ref: "r-alipay-ua" },
        headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 AliApp(AP/10.5.36.6000) AlipayClient/10.5.36.6000" }
    expect(response).to have_http_status(:ok)
  end

  it "lists eligible gateways with the default first" do
    make_eligible("wechat_pay")
    Payments::SetDefaultGateway.call(customer: customer, provider: "wechat_pay")
    create_order("r-list")

    get checkout_path, params: { ref: "r-list" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('value="alipay"')
    expect(response.body).to include('value="wechat_pay"')
    # the customer default (wechat_pay) is rendered before alipay
    expect(response.body.index('value="wechat_pay"')).to be < response.body.index('value="alipay"')
  end

  it "does not list a CNY-only gateway for a USD order" do
    make_eligible("stripe")
    create_order("r-usd-filter", currency: "USD")

    get checkout_path, params: { ref: "r-usd-filter" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('value="stripe"')
    expect(response.body).not_to include('value="alipay"')
  end

  it "POST with no provider falls back to the default gateway" do
    make_eligible("wechat_pay")
    Payments::SetDefaultGateway.call(customer: customer, provider: "wechat_pay")
    create_order("r-fallback", amount: 3.00)

    post checkout_path, params: { ref: "r-fallback" }
    expect(response).to have_http_status(:ok)
    expect(Payments::Payment.last.provider).to eq("wechat_pay")
  end

  it "renders the empty-state (no 500) when no gateway is eligible and no provider given" do
    # Disable the only eligible gateway → nothing eligible, no default.
    Payments::MerchantAccount.unscoped_by_tenant.where(customer_id: customer.id).update_all(status: "disabled")
    create_order("r-none")

    post checkout_path, params: { ref: "r-none" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to match(/no payment methods/i)
  end

  it "returns 404 when the order does not exist" do
    # Anonymous callers cannot create orders by guessing/choosing a ref;
    # otherwise they could fabricate an order at any amount they choose.
    get checkout_path, params: { ref: "never-created" }
    expect(response).to have_http_status(:not_found)
  end

  it "POST creates a Payment against the existing order's amount" do
    create_order("r2", amount: 2.00, subject: "s2")
    post checkout_path, params: {
      ref: "r2", provider: "alipay"
    }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("payments--qr-poll")
    expect(Payments::Payment.last.amount).to eq(2.00)
  end

  it "re-renders checkout when Charge raises a gateway error" do
    create_order("r-charge-fail")
    allow(Payments::Gateway).to receive(:charge)
      .and_raise(Payments::Errors::ApiError, "psp down")

    post checkout_path, params: { ref: "r-charge-fail", provider: "alipay" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(I18n.t("comp_payments.flash.charge_failed"))
  end

  it "returns 404 when the Payments module is disabled" do
    FeatureModules::CustomerAssignment.find_by!(
      customer: customer, feature_module: payment_module
    ).update!(status: :suspended)
    create_order("r-off", amount: 2.00)

    expect {
      post checkout_path, params: { ref: "r-off", provider: "alipay" }
    }.not_to change(Payments::Payment, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "stamps the active handoff invocation's token onto the created payment" do
    ref = Payments::HandoffCompletion.order_reference("tok-live")
    create_order(ref, amount: 2.00)
    allow_any_instance_of(Payments::CheckoutsController)
      .to receive(:current_invocation)
      .and_return({ module_key: "payment", customer_id: customer.id, token: "tok-live",
                    input: { amount: 2.00, currency: "CNY" } }.with_indifferent_access)

    post checkout_path, params: { ref: ref, provider: "alipay" }

    expect(response).to have_http_status(:ok)
    expect(Payments::Payment.last.handoff_token).to eq("tok-live")
  end

  it "rejects substituting a cheaper same-tenant order during a payment handoff" do
    create_order("cheap-order", amount: 0.01)
    allow_any_instance_of(Payments::CheckoutsController).to receive(:current_invocation)
      .and_return({ module_key: "payment", customer_id: customer.id, token: "expensive-token",
                    input: { amount: 100.00, currency: "CNY" } }.with_indifferent_access)

    expect {
      post checkout_path, params: { ref: "cheap-order", provider: "alipay" }
    }.not_to change(Payments::Payment, :count)
    expect(response).to have_http_status(:forbidden)
    expect(Payments::Gateway).not_to have_received(:charge)
  end

  it "rejects a changed amount even when the derived handoff reference matches" do
    ref = Payments::HandoffCompletion.order_reference("changed-money")
    create_order(ref, amount: 0.01)
    allow_any_instance_of(Payments::CheckoutsController).to receive(:current_invocation)
      .and_return({ module_key: "payment", customer_id: customer.id, token: "changed-money",
                    input: { amount: 100.00, currency: "CNY" } }.with_indifferent_access)

    post checkout_path, params: { ref: ref, provider: "alipay" }
    expect(response).to have_http_status(:forbidden)
    expect(Payments::Gateway).not_to have_received(:charge)
  end

  it "rejects a cross-tenant handoff session at the charge boundary" do
    create_order("cross-session")
    allow_any_instance_of(Payments::CheckoutsController).to receive(:current_invocation)
      .and_raise(FeatureModules::CrossTenantViolation)

    post checkout_path, params: { ref: "cross-session", provider: "alipay" }
    expect(response).to have_http_status(:forbidden)
    expect(Payments::Gateway).not_to have_received(:charge)
  end

  it "does not stamp a token when the active invocation is for another module" do
    create_order("r-notok", amount: 2.00)
    allow_any_instance_of(Payments::CheckoutsController)
      .to receive(:current_invocation)
      .and_return({ module_key: "sms", token: "tok-x" }.with_indifferent_access)

    post checkout_path, params: { ref: "r-notok", provider: "alipay" }

    expect(Payments::Payment.last.handoff_token).to be_nil
  end

  it "ignores client-supplied amount and uses the server-side order" do
    # Even if the request tries to override amount, the controller
    # uses @order.amount (which was set server-side at order
    # creation time) — protecting against price tampering.
    create_order("r-tamper", amount: 10.00, subject: "real")
    post checkout_path, params: {
      ref: "r-tamper", amount: 0.01, provider: "alipay"
    }
    expect(Payments::Payment.last.amount).to eq(10.00)
  end

  it "rejects a genuinely unknown provider" do
    create_order("r3")
    post checkout_path, params: {
      ref: "r3", provider: "nonexistent_gateway"
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Order #r3")
    expect(response.body).to include("bg-red-50")
  end

  it "rejects a known provider that is not eligible for the tenant" do
    create_order("r-ineligible", currency: "USD")

    post checkout_path, params: { ref: "r-ineligible", provider: "paypal" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Payments::Payment.where(payment_order: Payments::Order.find_by!(external_ref: "r-ineligible"))).to be_empty
    expect(response.body).to include("bg-red-50")
  end

  it "refuses a second capture on an already-paid order" do
    order = create_order("r-paid", amount: 2.00)
    order.update!(status: "paid", paid_at: Time.zone.now)
    make_eligible("wechat_pay")

    expect {
      post checkout_path, params: { ref: "r-paid", provider: "wechat_pay" }
    }.not_to change(Payments::Payment, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("already been paid")
    expect(Payments::Gateway).not_to have_received(:charge)
  end

  it "status endpoint returns JSON when looked up by out_trade_no" do
    # The public status endpoint identifies payments by `out_trade_no`
    # (high-entropy provider-side id) rather than the sequential primary
    # key, so an attacker cannot enumerate payments by stepping through
    # integer ids.
    order = create_order("e_status")
    payment = create(:payment, payment_order: order, provider: "alipay", flow: "qr",
                      out_trade_no: "ots1", amount: 1.00, status: "succeeded")
    get "/#{customer.id}/payments/#{payment.out_trade_no}/status"
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("status" => "succeeded")
  end

  it "status endpoint returns the local status when Query raises" do
    order = create_order("e_status_qerr")
    payment = create(:payment, payment_order: order, provider: "alipay", flow: "qr",
                      out_trade_no: "ots-qerr", amount: 1.00, status: "pending")
    allow(Payments::Gateway).to receive(:query)
      .and_raise(Payments::Errors::ApiError, "timeout")

    get "/#{customer.id}/payments/#{payment.out_trade_no}/status"

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("status" => "pending")
  end

  it "status endpoint refuses lookups by integer primary key for anonymous callers" do
    order = create_order("e_status_idor")
    payment = create(:payment, payment_order: order, provider: "alipay", flow: "qr",
                      out_trade_no: "ots-idor", amount: 1.00, status: "succeeded")
    get "/#{customer.id}/payments/#{payment.id}/status"
    expect(response).to have_http_status(:not_found)
  end

  # Stripe card flow — WidgetCheckoutComponent replaces the deleted CardCheckoutComponent.
  # The vendor-agnostic WidgetCheckoutComponent renders the Stripe card controller and
  # save-card opt-in when the Stripe descriptor declares supports_save_card: true.
  context "Stripe card flow with authenticated member" do
    let(:member_user) { create(:user, :member, customer: customer) }

    before do
      make_eligible("stripe")
      allow(Payments::Gateway).to receive(:charge).and_return(
        prepay_payload: { client_secret: "pi_secret", publishable_key: "pk_test_x" }
      )
      # Ensure authentication module is enabled for the customer
      enable_module!("authentication", customer, name: "Authentication")
    end

    it "renders WidgetCheckoutComponent with the Stripe card Stimulus controller" do
      create_order("r_card", amount: 5.00)
      sign_in member_user
      post checkout_path, params: { ref: "r_card", provider: "stripe" }
      expect(response).to have_http_status(:ok)
      # WidgetCheckoutComponent mounts the payments--stripe-card Stimulus controller
      expect(response.body).to include('data-controller="payments--stripe-card"')
    end

    it "injects client-secret and publishable-key data attributes for Stripe" do
      create_order("r_attrs", amount: 5.00)
      sign_in member_user
      post checkout_path, params: { ref: "r_attrs", provider: "stripe" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("payments--stripe-card-client-secret-value")
      expect(response.body).to include("payments--stripe-card-publishable-key-value")
    end

    it "renders a Pay button for Stripe (renders_pay_button: true)" do
      create_order("r_paybtn", amount: 5.00)
      sign_in member_user
      post checkout_path, params: { ref: "r_paybtn", provider: "stripe" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("payments--stripe-card#submit")
    end

    it "renders the Stripe trust footer" do
      create_order("r_footer", amount: 5.00)
      sign_in member_user
      post checkout_path, params: { ref: "r_footer", provider: "stripe" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Secured by Stripe")
    end

    it "status-url is keyed on out_trade_no (not integer id)" do
      create_order("r_otn", amount: 5.00)
      sign_in member_user
      post checkout_path, params: { ref: "r_otn", provider: "stripe" }
      expect(response).to have_http_status(:ok)
      payment = Payments::Payment.last
      expect(response.body).to include(payment.out_trade_no)
      expect(response.body).not_to match(/payments--stripe-card-status-url-value="[^"]*\/#{payment.id}"/)
    end

    it "submits explicit save-card consent with provider selection before the intent is created" do
      create_order("r_save", amount: 5.00)
      sign_in member_user
      get checkout_path, params: { ref: "r_save" }
      expect(response).to have_http_status(:ok)
      form = Nokogiri::HTML(response.body).css("form").find { |node| node.at_css('button[name="provider"][value="stripe"]') }
      expect(form.at_css('input[type="checkbox"][name="save_card"]')).to be_present
      expect(form.at_css('input[name="save_card"]')["checked"]).to be_nil

      post form["action"], params: { ref: form.at_css('input[name="ref"]')["value"], provider: "stripe", save_card: "1" }

      expect(response).to have_http_status(:ok)
      expect(Payments::Gateway).to have_received(:charge).with(hash_including(save_card: true, user: member_user))
      expect(Nokogiri::HTML(response.body).css('input[name="save_card"]')).to be_empty
      expect(Payments::Payment.last.attempt_context["save_card"]).to be(true)
    end

    it "uses the resolved default provider for server-side save-card authorization" do
      create_order("r_default_save", amount: 5.00)
      sign_in member_user
      Payments::SetDefaultGateway.call(customer: customer, provider: "stripe")
      allow(Payments::Activities::Charge).to receive(:call).and_call_original

      post checkout_path, params: { ref: "r_default_save", save_card: "1" }

      expect(response).to have_http_status(:ok)
      expect(Payments::Activities::Charge).to have_received(:call).with(
        hash_including(provider: "stripe", save_card: true, user: member_user)
      )
    end

    it "does not allow a different tenant's member to save a card" do
      create_order("r_foreign_save", amount: 5.00)
      sign_in create(:user, :member, customer: create(:customer))
      allow(Payments::Activities::Charge).to receive(:call).and_call_original

      post checkout_path, params: { ref: "r_foreign_save", provider: "stripe", save_card: "1" }

      expect(response).to have_http_status(:ok)
      expect(Payments::Activities::Charge).to have_received(:call).with(hash_including(save_card: false, user: nil))
    end

    it "does NOT render save-card checkbox for anonymous shopper" do
      create_order("r_anon", amount: 5.00)
      # anonymous — no sign_in
      post checkout_path, params: { ref: "r_anon", provider: "stripe" }
      expect(response).to have_http_status(:ok)
      # The save-card section should not appear for anonymous shoppers
      # (allow_save_card: false means no checkbox is rendered)
      expect(response.body).not_to include("save_card")
    end
  end

  # PayPal card flow — Smart Buttons widget; no platform Pay button needed.
  # The vendor-agnostic WidgetCheckoutComponent renders the PayPal Stimulus
  # controller with the order-id / client-id data attributes.
  # Orders use currency "USD" — a currency PayPal supports — so the contract's
  # currency_supported_by_gateway check passes naturally without stubbing.
  context "PayPal card flow" do
    before do
      make_eligible("paypal")
      allow(Payments::Gateway).to receive(:charge).and_return(
        prepay_payload: {
          "paypal_order_id" => "ORDER123",
          "client_id"       => "test-client-id",
          "currency"        => "USD",
          "intent"          => "capture"
        }
      )
    end

    it "GET checkout shows PayPal as an eligible gateway option" do
      create_order("r_pp_get", amount: 5.00, currency: "USD")
      get checkout_path, params: { ref: "r_pp_get" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="paypal"')
    end

    it "renders WidgetCheckoutComponent with the PayPal Smart Buttons controller" do
      create_order("r_pp", amount: 5.00, currency: "USD")
      post checkout_path, params: { ref: "r_pp", provider: "paypal" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="payments--paypal-buttons"')
    end

    it "injects paypal-order-id data attribute from the prepay_payload" do
      create_order("r_pp_oid", amount: 5.00, currency: "USD")
      post checkout_path, params: { ref: "r_pp_oid", provider: "paypal" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-payments--paypal-buttons-paypal-order-id-value="ORDER123"')
    end

    it "injects client-id data attribute from the prepay_payload" do
      create_order("r_pp_cid", amount: 5.00, currency: "USD")
      post checkout_path, params: { ref: "r_pp_cid", provider: "paypal" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-payments--paypal-buttons-client-id-value="test-client-id"')
    end

    it "status-url value contains the payment's out_trade_no (not its integer id)" do
      create_order("r_pp_otn", amount: 5.00, currency: "USD")
      post checkout_path, params: { ref: "r_pp_otn", provider: "paypal" }
      expect(response).to have_http_status(:ok)
      payment = Payments::Payment.last
      # status-url must embed out_trade_no, not the sequential integer id
      expect(response.body).to include(payment.out_trade_no)
      expect(response.body).not_to match(/payments--paypal-buttons-status-url-value="[^"]*\/#{payment.id}"/)
    end

    it "renders the PayPal trust footer" do
      create_order("r_pp_footer", amount: 5.00, currency: "USD")
      post checkout_path, params: { ref: "r_pp_footer", provider: "paypal" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Secured by PayPal")
    end

    it "does NOT render a Pay button (PayPal Smart Buttons inject their own)" do
      create_order("r_pp_nobtn", amount: 5.00, currency: "USD")
      post checkout_path, params: { ref: "r_pp_nobtn", provider: "paypal" }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("paypal-buttons#submit")
    end

    it "does NOT render a save-card checkbox (PayPal does not support card vaulting in this integration)" do
      create_order("r_pp_nosave", amount: 5.00, currency: "USD")
      post checkout_path, params: { ref: "r_pp_nosave", provider: "paypal" }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("save_card")
    end

    # Multi-tenant isolation: a different customer without an active PayPal
    # MerchantAccount must not see PayPal as an eligible option.
    it "does not show PayPal for a customer without an active PayPal account" do
      other_customer = create(:customer)
      enable_module!("payment", other_customer, name: "Payments")
      Current.customer = other_customer
      # Give the other customer only alipay (no paypal)
      Payments::PlatformGateway.for_provider("alipay").update!(available: true)
      create(:payment_merchant_account, :alipay, customer: other_customer,
             merchant_id: "M-alipay-other")
      create_order("r_pp_isolation", amount: 5.00, customer: other_customer)

      get "/#{other_customer.id}/payments/checkout", params: { ref: "r_pp_isolation" }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('value="paypal"')
    end
  end
end
