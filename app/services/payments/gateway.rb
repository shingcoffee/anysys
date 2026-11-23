# frozen_string_literal: true

module Payments
  # Vendor-agnostic facade over the registered Payments::Gateways. Existing
  # payments use their committed merchant identity; new operations additionally
  # require active, configured and platform-available credentials.
  class Gateway
    class << self
      def charge(customer:, order:, payment:, flow:, openid: nil, save_card: false, request: nil, user: nil)
        validate_payment_order!(customer, order, payment)
        gw = gateway_for_payment(customer, payment, historical: false)
        # Only forward optional kwargs the concrete #charge declares so Alipay
        # / WeChat keep their original signatures.
        kwargs = {}
        kwargs[:save_card] = save_card if save_card_accepted?(gw)
        kwargs[:user] = user if user_accepted?(gw)
        if client_ip_accepted?(gw)
          # The request can be a retry from another device/network. Its IP must
          # not change the parameters behind the committed PSP operation key.
          ip = payment.attempt_context["client_ip"].to_s.presence
          kwargs[:client_ip] = ip if ip
        end
        gw.charge(order: order, payment: payment, flow: flow, openid: openid, **kwargs)
      end

      def query(customer:, payment:, merchant_account: nil)
        gateway = gateway_for_payment(customer, payment, merchant_account: merchant_account)
        billing_alipay?(payment) ? gateway.billing_query(payment: payment) : gateway.query(payment: payment)
      end

      def refund(customer:, payment:, refund:, merchant_account: nil)
        gateway = gateway_for_payment(customer, payment, merchant_account: merchant_account)
        billing_alipay?(payment) ? gateway.billing_refund(payment: payment, refund: refund) : gateway.refund(payment: payment, refund: refund)
      end

      def close(customer:, payment:, merchant_account: nil)
        gateway = gateway_for_payment(customer, payment, merchant_account: merchant_account)
        billing_alipay?(payment) ? gateway.billing_close(payment: payment) : gateway.close(payment: payment)
      end

      def subscribe(customer:, subscription:)
        gateway_for(customer, subscription.provider).subscribe(subscription: subscription)
      end

      def cancel_subscription(customer:, subscription:, merchant_account: nil)
        validate_subscription_customer!(customer, subscription)
        billing_account!(customer, subscription.provider, merchant_account) if subscription.billing_owned?
        gateway_for(customer, subscription.provider, merchant_account: merchant_account, historical: merchant_account.present?).cancel_subscription(subscription: subscription)
      end

      def charge_subscription(customer:, subscription:, payment:, merchant_account: nil)
        validate_subscription_customer!(customer, subscription)
        raise Payments::Errors::TenantMismatch, "subscription payment provider mismatch" unless payment.provider == subscription.provider
        billing_account!(customer, subscription.provider, merchant_account) if subscription.billing_owned?
        gateway_for_payment(customer, payment, merchant_account: merchant_account, historical: false).charge_subscription(subscription: subscription, payment: payment)
      end

      def download_bill(customer:, provider:, bill_date:, bill_type:)
        gateway_for(customer, provider).download_bill(bill_date: bill_date, bill_type: bill_type)
      end

      # Tokenization API — only valid for gateways with :tokenized_cards capability.
      def vault_card(customer:, user:, provider:, return_url:)
        gateway_for(customer, provider).vault_card(user: user, return_url: return_url)
      end

      def charge_token(customer:, order:, payment:, payment_method:)
        validate_payment_order!(customer, order, payment)
        unless payment_method.provider == payment.provider
          raise Payments::Errors::TenantMismatch, "token provider differs from committed payment provider"
        end
        gateway_for_payment(customer, payment, historical: false).charge_token(
          order: order, payment: payment, payment_method: payment_method
        )
      end

      def detach_token(customer:, payment_method:, merchant_account: nil)
        raise Payments::Errors::TenantMismatch, "token customer mismatch" unless payment_method.customer_id == customer.id
        billing_account!(customer, payment_method.provider, merchant_account) if payment_method.billing_token?
        gateway_for(customer, payment_method.provider, merchant_account: merchant_account, historical: merchant_account.present?).detach_token(payment_method: payment_method)
      end

      def billing_vault_card(customer:, payment_method:, return_url:, merchant_account:)
        billing_method_account!(customer, payment_method, merchant_account)
        validate_billing_authorization_context!(payment_method.payments_subscription, merchant_account)
        gateway_for(customer, "stripe", merchant_account: merchant_account).billing_vault_card(
          payment_method: payment_method, return_url: return_url)
      end

      def billing_setup_intent(customer:, payment_method:, merchant_account:)
        billing_method_account!(customer, payment_method, merchant_account)
        gateway_for(customer, "stripe", merchant_account: merchant_account, historical: true)
          .billing_setup_intent(authorization_reference: payment_method.authorization_reference)
      end

      def billing_cancel_setup_intent(customer:, payment_method:, merchant_account:)
        billing_method_account!(customer, payment_method, merchant_account)
        gateway_for(customer, "stripe", merchant_account: merchant_account, historical: true)
          .billing_cancel_setup_intent(authorization_reference: payment_method.authorization_reference)
      end

      def billing_find_setup_intent(customer:, payment_method:, merchant_account:)
        billing_method_account!(customer, payment_method, merchant_account)
        gateway_for(customer, "stripe", merchant_account: merchant_account, historical: true)
          .billing_find_setup_intent(billing_payment_method_id: payment_method.id)
      end

      def billing_agreement(customer:, subscription:, merchant_account:, return_url: nil)
        validate_subscription_customer!(customer, subscription)
        billing_account!(customer, subscription.provider, merchant_account)
        raise Payments::Errors::TenantMismatch, "agreement is not billing-owned" unless subscription.billing_owned?
        validate_billing_authorization_context!(subscription, merchant_account) if return_url
        gateway = gateway_for(customer, subscription.provider, merchant_account: merchant_account, historical: return_url.nil?)
        return gateway.billing_authorization(subscription: subscription, return_url: return_url) if return_url
        gateway.query_agreement(subscription: subscription)
      end

      def billing_query(customer:, payment:, merchant_account:)
        billing_account!(customer, payment.provider, merchant_account)
        gateway = gateway_for_payment(customer, payment, merchant_account: merchant_account)
        payment.provider == "stripe" || billing_alipay?(payment) ? gateway.billing_query(payment: payment) : gateway.query(payment: payment)
      end

      def fetch_payment_method(customer:, provider:, psp_pm_id:, merchant_account: nil, historical: false)
        raise Payments::Errors::CredentialsMissing, "historical card fetch requires an explicit merchant" if historical && merchant_account.nil?
        gateway_for(customer, provider, merchant_account: merchant_account, historical: historical)
          .fetch_payment_method(psp_pm_id)
      end

      # Lightweight ping for the admin "Test connection" button.
      # Loads the tenant-scoped account for (customer, provider, mode) and calls
      # gateway#ping. Returns { ok:, message:, verified_at: }.
      # Does NOT require status: "active" — admins may test before enabling.
      def test_connection(customer:, provider:, mode:)
        acc = Payments::MerchantAccount.unscoped_by_tenant
                                       .find_by(customer_id: customer.id, provider: provider, mode: mode)
        return { ok: false, message: I18n.t("comp_payments.flash.no_account_row", provider: provider, mode: mode), verified_at: Time.current } unless acc

        Payments::Gateways.for(provider).new(account: acc).ping
      rescue ArgumentError
        { ok: false, message: I18n.t("comp_payments.test_connection.unknown_gateway"), verified_at: Time.current }
      end

      def gateway_for_merchant(provider:, merchant_id:)
        acc = CredentialResolver.by_merchant_id(provider: provider, merchant_id: merchant_id)
        Payments::Gateways.for(provider).new(account: acc)
      end

      private

      # True when the concrete gateway instance's #charge method declares a
      # :save_card keyword parameter. Uses Ruby reflection to avoid coupling
      # the facade to any specific gateway implementation.
      def save_card_accepted?(gateway_instance)
        gateway_instance.method(:charge).parameters.any? { |type, name| name == :save_card }
      end

      def user_accepted?(gateway_instance)
        gateway_instance.method(:charge).parameters.any? { |type, name| name == :user }
      end

      def client_ip_accepted?(gateway_instance)
        gateway_instance.method(:charge).parameters.any? { |type, name| name == :client_ip }
      end

      def gateway_for_payment(customer, payment, merchant_account: nil, historical: true)
        acc = CredentialResolver.for_payment(customer: customer, payment: payment, historical: historical)
        if merchant_account && merchant_account.id != acc.id
          raise Payments::Errors::TenantMismatch, "explicit account differs from committed payment merchant"
        end
        gateway_for(customer, payment.provider, merchant_account: acc, historical: historical)
      end

      def gateway_for(customer, provider, merchant_account: nil, historical: false)
        acc = merchant_account || CredentialResolver.call(customer: customer, provider: provider)
        unless acc.customer_id == customer.id && acc.provider == provider.to_s
          raise Payments::Errors::TenantMismatch, "gateway account binding mismatch"
        end
        unless historical || (acc.mode == CredentialResolver.default_mode && acc.configured? &&
                              Payments::PlatformGateway.available_providers.include?(acc.provider))
          raise Payments::Errors::CredentialsMissing, "gateway account is unavailable for new operations"
        end
        Payments::Gateways.for(provider).new(account: acc)
      end

      def validate_subscription_customer!(customer, subscription)
        raise Payments::Errors::TenantMismatch, "subscription customer mismatch" unless subscription.customer_id == customer.id
      end

      def validate_payment_order!(customer, order, payment)
        unless order.customer_id == customer.id && payment.customer_id == customer.id && payment.payment_order_id == order.id
          raise Payments::Errors::TenantMismatch, "gateway payment/order/customer binding mismatch"
        end
      end

      def billing_alipay?(payment)
        payment.provider == "alipay" && payment.attempt_context["operation"] == "billing_collection"
      end

      def billing_account!(customer, provider, account)
        raise Payments::Errors::CredentialsMissing, "billing operation requires its pinned merchant account" unless account
        unless customer.id == Billing::Collector::PLATFORM_OWNER_CUSTOMER_ID && account.customer_id == customer.id && account.provider == provider.to_s
          raise Payments::Errors::TenantMismatch, "billing platform merchant mismatch"
        end
      end

      def billing_method_account!(customer, payment_method, account)
        billing_account!(customer, payment_method.provider, account)
        unless payment_method.provider == "stripe" && payment_method.merchant_account_id == account.id
          raise Payments::Errors::TenantMismatch, "billing setup merchant mismatch"
        end
      end

      def validate_billing_authorization_context!(subscription, account)
        context = subscription.metadata.fetch("billing_authorization_context", {})
        if context.present? && (context["merchant_account_id"] != account.id || context["provider"] != account.provider ||
            context["merchant_id"] != account.merchant_id || context["mode"] != account.mode)
          raise Payments::Errors::CredentialsMissing, "billing setup merchant configuration changed"
        end
      end
    end
  end
end
