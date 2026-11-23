# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/billing/payment_methods", type: :request do
  include_context "admin records"
  let!(:method) { create(:billing_payment_method, customer: customer, provider: "stripe", request_key: SecureRandom.uuid) }
  let(:request_key) { SecureRandom.uuid }
  let(:payload) { { billing_payment_method: { request_key: request_key, provider: "stripe" } } }
  let(:action) { { kind: :stripe_setup, publishable_key: "pk_test_billing", client_secret: "seti_exact_secret" } }
  let(:path) { admin_settings_billing_payment_methods_path(customer.id) }
  let(:guard_path) { path }
  let(:server_host) { "www.example.com" }

  before { host! server_host }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :post

  {
    setup_intent: :post, authorization: :get, confirmation: :post, make_default: :patch, destroy: :delete
  }.each do |action_name, verb|
    describe "#{action_name} guard" do
      let(:guard_path) do
        case action_name
        when :setup_intent then setup_intent_admin_settings_billing_payment_methods_path(customer.id)
        when :destroy then admin_settings_billing_payment_method_path(customer.id, method)
        else public_send("#{action_name}_admin_settings_billing_payment_method_path", customer.id, method)
        end
      end
      it_behaves_like "an admin-guarded request", verb
    end
  end

  describe "authorized requests" do
    before { sign_in admin }

    it "resolves a provider return to the exact scoped method without activating it" do
      expect(Billing::PaymentAuthorization).not_to receive(:confirm!)
      get path, params: { authorization_request_key: method.request_key, setup_intent: "seti_forged" }
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(authorization_admin_settings_billing_payment_method_path(customer.id, method))
      expect(method.reload.status).to eq("pending")
    end

    it "cannot resolve a different customer's setup request key" do
      other_method = create(:billing_payment_method, customer: create(:customer), request_key: SecureRandom.uuid)
      expect(Billing::PaymentAuthorization).not_to receive(:confirm!)
      get path, params: { authorization_request_key: other_method.request_key }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "shows pending and failed rows without resolving authorization secrets on the list" do
      method.update!(display_label: "Pending Own Method")
      create(:billing_payment_method, :failed, customer: customer, display_label: "Failed Own Method")
      expect(Billing::PaymentAuthorization).not_to receive(:action_for)
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pending Own Method", "Failed Own Method")
      expect(response.body).not_to include("seti_exact_secret")
    end

    it "opens Add payment method once from the header and groups inactive methods" do
      allow(Billing::AvailableProviders).to receive(:call).and_return([
        { key: "stripe", label_key: "comp_payments.gateways.stripe.name", setup_kind: :stripe_setup, supported_currencies: %w[USD CNY] }
      ])
      create(:billing_payment_method, :active, customer: customer, provider: "stripe")
      get path
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.css('#billing-payment-methods header a[aria-controls="add-payment-method-dialog"]').size).to eq(1)
      expect(document.css("a").count { |node| node.text.include?(I18n.t("settings_billing.payment_methods.add")) }).to eq(1)
      expect(document.at_css("dialog#add-payment-method-dialog")).to be_present
      inactive = document.at_css("#inactive-payment-methods")
      expect(inactive.at_css("h3").text).to include(I18n.t("settings_billing.payment_methods.other_methods"))
      expect(inactive.at_css(%([data-payment-method-id="#{method.id}"]))).to be_present
    end

    it "blocks a tenant admin from another customer's payment methods index" do
      get admin_settings_billing_payment_methods_path(create(:customer).id)
      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
      expect(response.location.to_s).not_to include("sign_in")
    end

    it "provides the exact readiness props needed to expose a verified Make Default action" do
      create(:billing_subscription, customer: customer, currency: "CNY")
      mandate = create(:payment_subscription, customer: ensure_platform_customer, provider: "stripe", currency: "cny",
                        managed_by: "billing", next_charge_at: nil)
      method.update!(status: "active", payments_subscription: mandate)
      allow(Billing::AvailableProviders).to receive(:call).and_return([
        { key: "stripe", label_key: "comp_payments.gateways.stripe.name", setup_kind: :stripe_setup, supported_currencies: %w[USD CNY] }
      ])
      allow(Billing::Providers).to receive(:readiness_reason).with(payment_method: method).and_return(nil)
      expect_any_instance_of(Admin::Settings::Billing::PaymentMethodsController).to receive(:render)
        .and_wrap_original do |original, *args, **kwargs|
          facts = original.receiver.instance_variable_get(:@payment_method_readiness).fetch(method.id)
          expect(facts).to include(active: true, removed: false, enabled: true, currency_compatible: true,
                                  charge_ready: true, default_eligible: true, reason: nil)
          original.call(*args, **kwargs)
        end
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(make_default_admin_settings_billing_payment_method_path(customer.id, method))
    end

    it "does not present a CNY mandate as ready for the purchasing tenant's USD subscription" do
      create(:billing_subscription, customer: customer, currency: "USD")
      mandate = create(:payment_subscription, customer: ensure_platform_customer, provider: "stripe", currency: "cny",
                        managed_by: "billing", next_charge_at: nil)
      method.update!(status: "active", payments_subscription: mandate)
      allow(Billing::AvailableProviders).to receive(:call).and_return([
        { key: "stripe", label_key: "comp_payments.gateways.stripe.name", setup_kind: :stripe_setup, supported_currencies: %w[USD CNY] }
      ])
      allow(Billing::Providers).to receive(:readiness_reason).with(payment_method: method).and_return(nil)
      expect_any_instance_of(Admin::Settings::Billing::PaymentMethodsController).to receive(:render)
        .and_wrap_original do |original, *args, **kwargs|
          facts = original.receiver.instance_variable_get(:@payment_method_readiness).fetch(method.id)
          expect(facts).to include(enabled: true, currency_compatible: false, charge_ready: false,
                                  default_eligible: false, reason: :currency_mismatch)
          original.call(*args, **kwargs)
        end
      get path
      expect(response.body).not_to include(make_default_admin_settings_billing_payment_method_path(customer.id, method))
    end

    it "keeps provider availability distinct from a compatible mandate's currency" do
      create(:billing_subscription, customer: customer, currency: "CNY")
      mandate = create(:payment_subscription, customer: ensure_platform_customer, provider: "stripe", currency: "cny",
                        managed_by: "billing", next_charge_at: nil)
      method.update!(status: "active", payments_subscription: mandate)
      allow(Billing::AvailableProviders).to receive(:call).and_return([])
      allow(Billing::Providers).to receive(:readiness_reason).with(payment_method: method).and_return(nil)
      expect_any_instance_of(Admin::Settings::Billing::PaymentMethodsController).to receive(:render)
        .and_wrap_original do |original, *args, **kwargs|
          facts = original.receiver.instance_variable_get(:@payment_method_readiness).fetch(method.id)
          expect(facts).to include(active: true, enabled: false, currency_compatible: true,
                                  charge_ready: false, default_eligible: false, reason: :provider_unavailable)
          original.call(*args, **kwargs)
        end
      get path
      expect(response.body).not_to include(make_default_admin_settings_billing_payment_method_path(customer.id, method))
    end

    it "presents removed status explicitly and never enables defaulting" do
      method.update!(status: "removed", removed_at: Time.current)
      expect_any_instance_of(Admin::Settings::Billing::PaymentMethodsController).to receive(:render)
        .and_wrap_original do |original, *args, **kwargs|
          facts = original.receiver.instance_variable_get(:@payment_method_readiness).fetch(method.id)
          expect(facts).to include(active: false, removed: true, charge_ready: false,
                                  default_eligible: false, reason: :method_removed)
          original.call(*args, **kwargs)
        end
      get path
      expect(response).to have_http_status(:ok)
    end

    it "supplies provider descriptors and the exact scoped confirmation/result paths on the authorization screen" do
      allow(Billing::PaymentAuthorization).to receive(:action_for).and_return(action)
      allow(Billing::AvailableProviders).to receive(:call).and_return([
        { key: "stripe", label_key: "comp_payments.gateways.stripe.name", setup_kind: :stripe_setup, supported_currencies: %w[USD CNY] }
      ])
      get authorization_admin_settings_billing_payment_method_path(customer.id, method)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(confirmation_admin_settings_billing_payment_method_url(customer.id, method))
      expect(response.body).to include(authorization_admin_settings_billing_payment_method_url(customer.id, method))
      expect(response.body).to include(method.request_key, "seti_exact_secret")
      expect(response.headers["Cache-Control"]).to include("no-store")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("[data-billing-tabs] a[aria-current='page']")["href"])
        .to eq(admin_settings_billing_payment_methods_path(customer.id))
    end

    it "returns the exact Stripe setup envelope without model/account secrets" do
      expect(Billing::Activities::SetUpPaymentMethod).to receive(:call).with(
        customer: customer, actor: admin, provider: "stripe", request_key: request_key,
        return_url: admin_settings_billing_payment_methods_url(customer.id, host: server_host)
      ).and_return(Billing::Result.new(status: :authorization_required, payment_method: method,
                                       action: action.merge(secret_key: "never-serialize")))
      post setup_intent_admin_settings_billing_payment_methods_path(customer.id), params: {
        billing_payment_method: payload[:billing_payment_method].merge(provider: "alipay", amount_cents: 1,
          customer_id: create(:customer).id, merchant_account_id: 2, payment_method_id: "pm_forged",
          return_url: "https://attacker.example/")
      }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "payment_method_id" => method.id, "status" => "authorization_required",
        "confirmation_url" => confirmation_admin_settings_billing_payment_method_url(customer.id, method, host: server_host),
        "client_secret" => "seti_exact_secret",
        "action" => { "kind" => "stripe_setup", "publishable_key" => "pk_test_billing", "client_secret" => "seti_exact_secret" }
      )
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).not_to include("never-serialize", "merchant_account_id", "credentials")
    end

    it "queries only the scoped persisted method on confirmation, ignoring PSP hints" do
      expect(Billing::PaymentAuthorization).to receive(:confirm!).with(payment_method: method)
        .and_return(Billing::Result.new(status: :pending, payment_method: method))
      post confirmation_admin_settings_billing_payment_method_path(customer.id, method),
           params: { setup_intent_id: "seti_someone_else", payment_method_id: "pm_forged", status: "active" }, as: :json
      expect(response).to have_http_status(:accepted)
      expect(method.reload.status).to eq("pending")
    end

    it "does not activate or query the provider on a return GET" do
      expect(Billing::PaymentAuthorization).to receive(:action_for).with(
        payment_method: method, return_url: authorization_admin_settings_billing_payment_method_url(customer.id, method, host: server_host)
      ).and_return(action)
      expect(Billing::PaymentAuthorization).not_to receive(:confirm!)
      get authorization_admin_settings_billing_payment_method_path(customer.id, method),
          params: { setup_intent: "seti_forged", redirect_status: "succeeded" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(method.reload.status).to eq("pending")
    end

    it "rejects an off-provider authorization destination" do
      method.update!(provider: "alipay")
      allow(Billing::Activities::SetUpPaymentMethod).to receive(:call).and_return(
        Billing::Result.new(status: :authorization_required, payment_method: method,
                            action: { kind: :redirect, url: "https://openapi.alipay.com.attacker.example/gateway.do" })
      )
      post path, params: payload, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include("attacker.example")
    end

    it "redirects to a controlled server-generated Alipay action with 303" do
      method.update!(provider: "alipay")
      url = "https://openapi.alipay.com/gateway.do?sign=server-signature"
      allow(Billing::Activities::SetUpPaymentMethod).to receive(:call).and_return(
        Billing::Result.new(status: :authorization_required, payment_method: method, action: { kind: :redirect, url: url })
      )
      post path, params: payload
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(url)
    end

    it "returns only normalized fields for a controlled Alipay provider form" do
      method.update!(provider: "alipay")
      form_action = { kind: :provider_form, action_url: "https://openapi.alipay.com/gateway.do", method: "post",
                      fields: { "app_id" => "server-app", "sign" => "server-sign" }, private_key: "never-serialize" }
      allow(Billing::Activities::SetUpPaymentMethod).to receive(:call).and_return(
        Billing::Result.new(status: :authorization_required, payment_method: method, action: form_action)
      )
      post path, params: payload, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["action"]).to eq(
        "kind" => "provider_form", "action_url" => "https://openapi.alipay.com/gateway.do", "method" => "post",
        "fields" => { "app_id" => "server-app", "sign" => "server-sign" }
      )
      expect(response.parsed_body).not_to have_key("client_secret")
      expect(response.body).not_to include("never-serialize")
    end

    it "uses B's default command without directly mutating another default" do
      expect(Billing::Activities::MakeDefaultPaymentMethod).to receive(:call).with(customer: customer, payment_method: method)
        .and_return(Billing::Result.new(status: :invalid, reason: :method_not_ready))
      patch make_default_admin_settings_billing_payment_method_path(customer.id, method), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(method.reload.is_default).to be(false)
    end

    it "allows pending/failed method removal through the domain API" do
      expect(Billing::Activities::RemovePaymentMethod).to receive(:call).with(payment_method: method)
        .and_return(Billing::Result.new(status: :removed, payment_method: method))
      delete admin_settings_billing_payment_method_path(customer.id, method)
      expect(response).to have_http_status(:see_other)
    end

    it "retains invalid request identities without calling the PSP setup command" do
      expect(Billing::Activities::SetUpPaymentMethod).not_to receive(:call)
      post setup_intent_admin_settings_billing_payment_methods_path(customer.id),
           params: { billing_payment_method: { request_key: "bad" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not rescue a uniqueness race as a false authorization success" do
      allow(Billing::Activities::SetUpPaymentMethod).to receive(:call).and_return(
        Billing::Result.new(status: :invalid, reason: :authorization_conflict)
      )
      post path, params: payload, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:notice]).to be_nil
    end

    { authorization: :get, confirmation: :post, make_default: :patch, destroy: :delete }.each do |action_name, verb|
      it "denies a foreign method ID on #{action_name} after a real authenticated GET" do
        other_method = create(:billing_payment_method, customer: create(:customer))
        expect(Billing::PaymentAuthorization).not_to receive(:action_for)
        expect(Billing::PaymentAuthorization).not_to receive(:confirm!)
        expect(Billing::Activities::RemovePaymentMethod).not_to receive(:call)
        expect(Billing::Activities::MakeDefaultPaymentMethod).not_to receive(:call)
        get path
        expect(response).to have_http_status(:ok)
        target = if action_name == :destroy
                   admin_settings_billing_payment_method_path(customer.id, other_method)
                 else
                   public_send("#{action_name}_admin_settings_billing_payment_method_path", customer.id, other_method)
                 end
        public_send(verb, target, as: :json)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  it "uses the URL purchasing customer when an owner sets up a tenant method" do
    sign_in find_or_create_platform_owner
    expect(Billing::Activities::SetUpPaymentMethod).to receive(:call).with(
      customer: customer, actor: find_or_create_platform_owner, provider: "stripe", request_key: request_key,
      return_url: admin_settings_billing_payment_methods_url(customer.id, host: server_host)
    ).and_return(Billing::Result.new(status: :pending, payment_method: method))
    post setup_intent_admin_settings_billing_payment_methods_path(customer.id), params: payload, as: :json
    expect(response).to have_http_status(:accepted)
  end

  describe "platform owner payment methods reads" do
    before { sign_in find_or_create_platform_owner }

    it "returns 200 on /81721200/admin/settings/billing/payment_methods" do
      get admin_settings_billing_payment_methods_path(find_or_create_platform_owner.customer.id)
      expect(response).to have_http_status(:ok)
    end

    it "lists only the URL customer's methods on a tenant path" do
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(data-payment-method-id="#{method.id}"))
      foreign = create(:billing_payment_method, customer: create(:customer), display_label: "Foreign Method XYZ")
      get path
      expect(response.body).not_to include(%(data-payment-method-id="#{foreign.id}"))
      expect(response.body).not_to include("Foreign Method XYZ")
    end
  end
end
