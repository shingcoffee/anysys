# frozen_string_literal: true

module Billing
  module Activities
    class SetUpPaymentMethod
      def self.call(customer:, actor:, provider:, return_url:, request_key:)
        raise ArgumentError, "setup must run after domain commit" if PaymentMethod.connection.transaction_open?
        unless actor && ((actor.admin? && actor.customer_id == customer.id) || (actor.owner? && actor.customer_id == Collector::PLATFORM_OWNER_CUSTOMER_ID))
          return Billing::Result.new(status: :invalid, reason: :admin_required)
        end
        scope = PaymentMethod.unscoped_by_tenant.where(customer_id: customer.id, request_key: request_key)
        method = scope.first
        if method && (method.provider != provider.to_s || method.removed?)
          return Billing::Result.new(status: :invalid, payment_method: method, reason: :request_key_used)
        end
        if method&.active?
          reason = Providers.readiness_reason(payment_method: method)
          return Billing::Result.new(status: reason ? :invalid : :active, payment_method: method, reason: reason)
        end
        if method&.authorization_expires_at && method.authorization_expires_at <= Time.current
          return Billing::Result.new(status: :invalid, payment_method: method, reason: :authorization_expired)
        end
        subscription = Entitlements.current_subscription(customer: customer)
        currency = subscription&.currency || CurrencyResolver.for_customer(customer)
        form = Contracts::PaymentMethod.new(method || PaymentMethod.new)
        form.customer, form.currency = customer, currency
        unless form.validate(provider: provider, request_key: request_key)
          return Billing::Result.new(status: :invalid, payment_method: method, form: form, errors: form.errors.messages, reason: :provider_unavailable)
        end
        cycle = subscription&.interval || "monthly"
        if provider.to_s == "alipay" && cycle != "monthly"
          return Billing::Result.new(status: :invalid, payment_method: method, reason: :reauthorization_required)
        end
        uri = URI.parse(return_url)
        unless %w[https http].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil? && uri.path.start_with?("/#{customer.id}/admin/settings/billing/")
          return Billing::Result.new(status: :invalid, reason: :invalid_return_url)
        end
        Billing::Result.transaction(customer) do
          method = scope.first
          if method && (method.provider != provider.to_s || method.removed?)
            return Billing::Result.new(status: :invalid, payment_method: method, reason: :request_key_used)
          end
          unless method
            account = Payments::CredentialResolver.call(customer: Providers.platform, provider: provider.to_s)
            method = scope.create!(provider: provider, status: "pending", merchant_account_id: account.id, authorized_by_id: actor.id,
              requested_default: true, is_default: false, authorization_expires_at: 24.hours.from_now, revocation_state: "none")
            ceiling = authorization_ceiling(currency, cycle, subscription)
            mandate = Payments::Subscription.create!(customer_id: Collector::PLATFORM_OWNER_CUSTOMER_ID,
              provider: provider, currency: currency.downcase, cycle: cycle, amount: BigDecimal(ceiling.to_s) / 100,
              plan_name: I18n.t("settings_billing.payment_methods.mandate_name"),
              external_ref: "billing-pm-#{customer.id}-#{provider}-#{method.id}", status: "pending_sign",
              managed_by: "billing", metadata: { "billing_owned" => true, "billing_payment_method_id" => method.id, "billing_customer_id" => customer.id,
                "billing_authorization_context" => { "merchant_account_id" => account.id, "provider" => account.provider,
                  "merchant_id" => account.merchant_id, "mode" => account.mode } }, next_charge_at: nil)
            method.update!(payments_subscription: mandate,
              authorization_reference: provider.to_s == "alipay" ? mandate.external_ref : nil)
          end
        end
        uri.path = "/#{customer.id}/admin/settings/billing/payment_methods/#{method.id}/authorization"
        return_url = uri.to_s
        setup = Providers.for(method).setup(return_url: return_url)
        Billing::Result.transaction(customer) do
          method.reload
          if provider.to_s == "stripe"
            reference = setup.fetch(:setup_intent_id)
            raise Payments::Errors::TenantMismatch, "setup intent correlation changed" if method.authorization_reference.present? && method.authorization_reference != reference
            method.update!(authorization_reference: reference)
            PaymentAuthorization.ensure_stripe_token!(method, setup.fetch(:psp_customer_id))
          end
        end
        return Billing::Result.new(status: :invalid, payment_method: method, reason: :method_removed) if method.removed?
        return Billing::Result.new(status: :active, payment_method: method) if method.active?
        return PaymentAuthorization.confirm!(payment_method: method) unless setup[:action]
        Billing::Result.new(status: :authorization_required, payment_method: method, action: setup.fetch(:action))
      rescue Payments::Errors::TransportError
        method&.update!(failure_code: "authorization_unknown") unless method&.removed? || method&.active?
        Billing::Result.new(status: :pending, payment_method: method, reason: :authorization_unknown)
      rescue Payments::Errors::CredentialsMissing
        Billing::Result.new(status: :invalid, payment_method: method, reason: :provider_unavailable)
      rescue Payments::Errors::ApiError => error
        method&.update!(status: "failed", failure_code: Providers.failure_code(error)) unless method&.removed? || method&.active?
        Billing::Result.new(status: :invalid, payment_method: method, reason: :authorization_failed)
      rescue URI::InvalidURIError
        Billing::Result.new(status: :invalid, reason: :invalid_return_url)
      rescue ActiveRecord::RecordNotUnique
        method = scope.first!
        Billing::Result.new(status: method.active? ? :active : :pending, payment_method: method, reason: :concurrent_authorization)
      end

      def self.authorization_ceiling(currency, cycle, subscription)
        # Compare only prices in the actual authorization currency/cadence.
        catalog = Billing::Plan.active.where(interval: cycle).map { |plan| plan.price_cents_for(currency) }.max.to_i
        base = [catalog, subscription&.amount_cents.to_i, 1].max
        issued = if subscription
          subscription.invoices.where(currency: currency, status: %w[open uncollectible])
            .select { |invoice| invoice.terms_snapshot["interval"] == cycle }.map(&:total_cents).max.to_i
        else
          0
        end
        [base + base * Billing::Settings.current.tax_rate_bps / 10_000, issued, 1].max
      end
      private_class_method :authorization_ceiling
    end
  end
end
