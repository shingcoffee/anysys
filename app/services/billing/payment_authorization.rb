# frozen_string_literal: true

module Billing
  module PaymentAuthorization
    # Construct this only after the shared webhook dispatcher has verified the
    # signature with this exact merchant account, or after our server query.
    VerifiedEvent = Data.define(:merchant_account_id, :provider, :payload)

    class << self
      def verified_event(account:, payload:)
        VerifiedEvent.new(merchant_account_id: account.id, provider: account.provider,
          payload: Billing::Result.freeze_value(payload.deep_stringify_keys.deep_dup))
      end

      # Shared signed webhook hook. nil means the event is not a billing setup
      # or agreement. A non-nil Result must be projected before ACK/processed.
      def handle_verified_event!(account:, payload:)
        data = payload.deep_stringify_keys
        if account.provider == "stripe" && data["type"].to_s.start_with?("setup_intent.")
          object = data.dig("data", "object") || {}
          id = object.dig("metadata", "billing_payment_method_id")
          return nil if id.blank?
          method = PaymentMethod.unscoped_by_tenant.find_by(id: id, merchant_account_id: account.id, provider: "stripe")
          raise Payments::Errors::TenantMismatch, "billing setup correlation unavailable" unless method
          data = object
        elsif account.provider == "alipay" && alipay_agreement_event?(data) && (data["external_agreement_no"].present? || data["agreement_no"].present?)
          if data["external_agreement_no"].present?
            return nil unless data["external_agreement_no"].start_with?("billing-pm-")
            method = PaymentMethod.unscoped_by_tenant.find_by(merchant_account_id: account.id, provider: "alipay", authorization_reference: data["external_agreement_no"])
            raise Payments::Errors::TenantMismatch, "billing agreement correlation unavailable" unless method
          else
            mandate = Payments::Subscription.unscoped_by_tenant.find_by(customer_id: account.customer_id, provider: "alipay", psp_agreement_id: data["agreement_no"], managed_by: "billing")
            return nil unless mandate
            method = PaymentMethod.unscoped_by_tenant.find_by!(payments_subscription_id: mandate.id, merchant_account_id: account.id)
            data = data.merge("external_agreement_no" => mandate.external_ref)
          end
        else
          return nil
        end
        confirm!(payment_method: method, verified_event: verified_event(account: account, payload: data))
      end

      def confirm!(payment_method:, verified_event: nil)
        method = payment_method
        event = verified_event
        if event
          unless event.is_a?(VerifiedEvent) && event.merchant_account_id == method.merchant_account_id && event.provider == method.provider
            raise Payments::Errors::TenantMismatch, "unverified or mismatched billing authorization"
          end
          if method.provider == "stripe"
            payload = event.payload
            validate_stripe_identity!(method, payload)
            # A signed early webhook can establish the returned intent reference.
            Billing::Result.transaction(method.customer) do
              method.reload
              if method.authorization_reference.present? && method.authorization_reference != payload.fetch("id")
                raise Payments::Errors::TenantMismatch, "different setup intent"
              end
              method.update!(authorization_reference: payload.fetch("id"))
            end
            # Retrieve card/customer binding rather than attach a browser token.
            payload = Providers.for(method).query
          else
            payload = event.payload
            payload = Providers.for(method).query if (payload["status"] || payload["agreement_status"]).blank?
          end
        else
          return Billing::Result.new(status: :pending, payment_method: method) if method.authorization_reference.blank? && method.provider != "stripe"
          payload = Providers.for(method).query
          return Billing::Result.new(status: :pending, payment_method: method) unless payload
          if method.provider == "stripe" && method.authorization_reference.blank?
            validate_stripe_identity!(method, payload)
            Billing::Result.transaction(method.customer) do
              method.reload
              raise Payments::Errors::TenantMismatch, "different setup intent" if method.authorization_reference.present? && method.authorization_reference != payload.fetch("id")
              method.update!(authorization_reference: payload.fetch("id"))
            end
          end
        end
        payload = payload.deep_stringify_keys
        Billing::Result.transaction(method.customer) do
          method.reload
          mandate = method.payments_subscription
          validate_mandate!(method, mandate)
          status = method.provider == "stripe" ? payload["status"] : (payload["status"] || payload["agreement_status"])
          if method.provider == "stripe"
            validate_stripe_identity!(method, payload)
            raise Payments::Errors::TenantMismatch, "different setup intent" unless method.authorization_reference == payload["id"]
          else
            unless payload["external_agreement_no"] == mandate.external_ref && payload["agreement_no"].present?
              raise Payments::Errors::TenantMismatch, "different Alipay agreement"
            end
          end
          revoked = method.provider == "stripe" ? status == "canceled" : %w[STOP EXPIRED UNSIGN].include?(status)
          if revoked
            mandate.update!(status: "cancelled", cancelled_at: Time.current, next_charge_at: nil)
            method.update!(status: method.removed? ? "removed" : "failed", is_default: false, failure_code: "authorization_revoked")
            return Billing::Result.new(status: :invalid, payment_method: method, reason: :authorization_revoked)
          end
          succeeded = method.provider == "stripe" ? status == "succeeded" : status == "NORMAL"
          return Billing::Result.new(status: :pending, payment_method: method) unless succeeded
          if Payments::Subscription::TERMINAL_STATUSES.include?(mandate.status) && !method.removed?
            method.update!(status: "failed", is_default: false, failure_code: "authorization_revoked")
            return Billing::Result.new(status: :invalid, payment_method: method, reason: :authorization_revoked)
          end
          if method.provider == "stripe"
            token = ensure_stripe_token!(method, identity(payload.fetch("customer")))
            card = payload.fetch("payment_method")
            unless card.is_a?(Hash) && card["type"] == "card" && identity(card["customer"]) == token.psp_customer_id && card.dig("card", "last4").present?
              raise Payments::Errors::TenantMismatch, "Stripe token is not bound to billing customer"
            end
            removing = method.removed? || (method.authorization_expires_at && method.authorization_expires_at <= Time.current && !method.active?)
            token.update!(psp_payment_method_id: card.fetch("id"), brand: card.dig("card", "brand"), last4: card.dig("card", "last4"),
              exp_month: card.dig("card", "exp_month"), exp_year: card.dig("card", "exp_year"), status: removing ? "removed" : "active")
            label = token.display_label
          else
            mandate.update!(psp_agreement_id: payload.fetch("agreement_no"))
            if payload["single_quota"].present?
              granted = BigDecimal(payload.fetch("single_quota").to_s)
              raise Payments::Errors::TenantMismatch, "invalid Alipay authorization ceiling" unless granted.positive?
              mandate.update!(amount: [mandate.amount, granted].min)
            end
            label = payload["alipay_logon_id"].presence || payload["buyer_logon_id"].presence
          end
          if method.removed? || (method.authorization_expires_at && method.authorization_expires_at <= Time.current && !method.active?)
            mandate.update!(status: "cancelled", next_charge_at: nil, cancelled_at: mandate.cancelled_at || Time.current)
            method.update!(status: "removed", removed_at: method.removed_at || Time.current, is_default: false,
              revocation_state: "pending", revocation_next_attempt_at: Time.current)
            return Billing::Result.new(status: :invalid, payment_method: method, reason: :method_removed)
          end
          mandate.update!(status: "active", signed_at: mandate.signed_at || Time.current, next_charge_at: nil)
          method.update!(status: "active", authorized_at: method.authorized_at || Time.current, display_label: label, failure_code: nil)
          if method.requested_default
            # A later accepted setup supersedes an older pending default request.
            newer = PaymentMethod.unscoped_by_tenant.where(customer_id: method.customer_id, requested_default: true).where("id > ?", method.id).where.not(status: %w[removed failed]).exists?
            unless newer || Providers.readiness_reason(payment_method: method)
              PaymentMethod.unscoped_by_tenant.where(customer_id: method.customer_id, is_default: true).where.not(id: method.id).update_all(is_default: false)
              method.is_default = true
            end
          end
          method.save! if method.changed?
          Billing::Result.new(status: :active, payment_method: method)
        end
      rescue Payments::Errors::TransportError, Payments::Errors::CredentialsMissing
        Billing::Result.new(status: :pending, payment_method: method, reason: :authorization_unknown)
      rescue Payments::Errors::ApiError
        Billing::Result.new(status: :pending, payment_method: method, reason: :authorization_unavailable)
      end

      # Existing Payments token/agreement callback can call this after its own
      # projection. With no verified envelope we confirm using a server query.
      def sync_payment_method!(payment_method: nil, subscription: nil, mandate: nil, verified_event: nil)
        mandate ||= subscription
        method = if payment_method.is_a?(Billing::PaymentMethod)
          payment_method
        else
          mandate ||= Payments::Subscription.unscoped_by_tenant.find_by(payment_method_id: payment_method&.id, managed_by: "billing")
          PaymentMethod.unscoped_by_tenant.find_by(payments_subscription_id: mandate&.id) if mandate
        end
        return nil unless method
        confirm!(payment_method: method, verified_event: verified_event)
      end

      # Read query for C's authorized GET. No activation writes, no browser proof.
      def action_for(payment_method:, return_url:)
        method = payment_method
        return nil unless method.status.in?(%w[pending failed]) && method.removed_at.nil?
        return nil if method.authorization_expires_at && method.authorization_expires_at <= Time.current
        return nil unless method.merchant_account && method.authorization_reference.present?
        validate_mandate!(method, method.payments_subscription)
        if method.provider == "stripe"
          # GET retrieves an existing intent only. It cannot create/replay setup,
          # persist a token/reference, or activate the mandate/method.
          intent = Providers.for(method).query
          validate_stripe_identity!(method, intent)
          raise Payments::Errors::TenantMismatch, "different setup intent" unless intent.fetch("id") == method.authorization_reference
          token = method.payments_subscription.payment_method
          raise Payments::Errors::TenantMismatch, "different Stripe customer" unless token && token.psp_customer_id == identity(intent.fetch("customer"))
          return nil unless %w[requires_payment_method requires_confirmation requires_action].include?(intent.fetch("status"))
          { kind: :stripe_setup, publishable_key: method.merchant_account.credential(:publishable_key), client_secret: intent.fetch("client_secret") }
        else
          available = AvailableProviders.call(customer: method.customer, currency: method.payments_subscription.currency)
          return nil unless available.any? { |option| option[:key] == method.provider }
          Providers.for(method).setup(return_url: return_url)[:action]
        end
      rescue Payments::Errors::Error
        nil
      end

      def ensure_stripe_token!(method, psp_customer_id)
        mandate = method.payments_subscription
        token = mandate.payment_method
        unless token
          token = Payments::PaymentMethod.create!(customer_id: Collector::PLATFORM_OWNER_CUSTOMER_ID, user_id: nil,
            billing_customer_id: method.customer_id, billing_authorized_by_id: method.authorized_by_id,
            provider: "stripe", psp_customer_id: psp_customer_id,
            psp_payment_method_id: "pending:#{method.authorization_reference}", status: "active", is_default: false)
          mandate.update!(payment_method: token)
        end
        unless token.provider == "stripe" && token.customer_id == Collector::PLATFORM_OWNER_CUSTOMER_ID && token.user_id.nil? && token.billing_customer_id == method.customer_id &&
          token.billing_authorized_by_id == method.authorized_by_id && token.psp_customer_id == psp_customer_id
          raise Payments::Errors::TenantMismatch, "billing vault token ownership mismatch"
        end
        token
      end

      private

      def identity(value) = value.is_a?(Hash) ? value["id"] : value

      def alipay_agreement_event?(payload)
        %w[NORMAL STOP EXPIRED UNSIGN].include?(payload["status"] || payload["agreement_status"]) ||
          payload["notify_type"].to_s.include?("agreement")
      end

      def validate_stripe_identity!(method, payload)
        metadata = payload["metadata"] || {}
        context = method.payments_subscription&.metadata&.fetch("billing_authorization_context", {}) || {}
        unless metadata["billing_payment_method_id"].to_s == method.id.to_s && metadata["billing_customer_id"].to_s == method.customer_id.to_s &&
          metadata["merchant_account_id"].to_s == method.merchant_account_id.to_s &&
          (context["merchant_id"].blank? || metadata["merchant_id"] == context["merchant_id"])
          raise Payments::Errors::TenantMismatch, "Stripe billing metadata mismatch"
        end
      end

      def validate_mandate!(method, mandate)
        unless mandate && mandate.customer_id == Collector::PLATFORM_OWNER_CUSTOMER_ID && mandate.billing_owned? &&
          mandate.provider == method.provider && mandate.external_ref == "billing-pm-#{method.customer_id}-#{method.provider}-#{method.id}" &&
          method.merchant_account && method.merchant_account.customer_id == mandate.customer_id && method.merchant_account.provider == method.provider
          raise Payments::Errors::TenantMismatch, "billing mandate identity mismatch"
        end
      end
    end
  end
end
