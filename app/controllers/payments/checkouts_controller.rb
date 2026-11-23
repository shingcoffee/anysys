# frozen_string_literal: true

require "ostruct"

module Payments
  # Public-by-design controller: shoppers need to open a checkout URL and poll
  # their own payment status without holding an authenticated session. The
  # controller resolves the tenant from the URL and pins every record lookup
  # to that tenant at the call site so a reordered before_action can't
  # introduce a cross-tenant leak.
  class CheckoutsController < ApplicationController
    # Reads the page → module handoff invocation from the session (tenant-checked).
    include FeatureModules::InvocationContext
    include ComponentPageRendering

    # Public-shopper pages render in a minimal storefront layout, not the
    # tenant dashboard shell (shoppers have no dashboard session).
    layout "payments_storefront"

    skip_before_action :authenticate_user!, raise: false

    before_action :set_customer
    before_action :require_payments_module!
    before_action :set_or_build_order, only: %i[show create]

    FLOW_COMPONENTS = {
      qr:    Payments::QrCodeComponent,
      h5:    Payments::H5RedirectComponent,
      jsapi: Payments::JsapiInvokerComponent
    }.freeze

    def show
      render Payments::CheckoutComponent.new(
        order:            @order,
        gateways:         eligible_gateways,
        default_provider: default_provider
      )
    end

    # Entry point for a page → payment handoff (Payment module `entry_path`).
    # Materializes a `Payments::Order` from the invocation input stashed in the
    # session, then hands the shopper to the checkout keyed by external_ref.
    #
    # Trust model: the order's amount/subject/currency come from the invocation,
    # which the page author's `input_mapping` resolved server-side — the checkout
    # itself never reads them from the shopper's request. A mapping MAY draw a
    # value from a submitted form field (e.g. a "pay what you want" amount), in
    # which case that value is shopper-supplied by the author's explicit choice;
    # the module input contract (amount > 0, currency, …) is the validation
    # boundary. Fixed prices should be mapped from a `literal` or `entity` source,
    # not a form field.
    #
    # The payer's note (user_fillable `body`) is collected beforehand by the
    # framework entry step (FeatureModules::HandoffsController); until then the
    # guard sends the shopper back there.
    def start
      invocation = require_module_invocation(FeatureModules::Payment::Registration.module_key,
                                             alert: t("comp_payments.flash.no_active_request")) or return

      order = build_order_from(invocation)
      redirect_to payment_checkout_path(@customer.id, ref: order.external_ref)
    rescue FeatureModules::CrossTenantViolation
      head :forbidden
    end

    def create
      provider = @resolved_provider = params[:provider].presence || default_provider

      # No provider chosen and none eligible → render the empty-state checkout
      # rather than charging with a nil provider (which would 500 downstream).
      if provider.blank?
        return render(Payments::CheckoutComponent.new(order: @order, gateways: eligible_gateways,
                                                      default_provider: default_provider),
                      status: :unprocessable_entity)
      end

      contract = Payments::Contracts::Charge.new(OpenStruct.new)
      attrs = {
        external_ref: @order.external_ref,
        amount: @order.amount,
        currency:     @order.currency,
        subject:      @order.subject,
        provider:     provider,
        openid:       params[:openid]
      }
      valid = contract.validate(attrs)
      provider_eligible = eligible_gateways.any? { |gateway| gateway.key.to_s == provider.to_s }
      contract.errors.add(:provider, :inclusion) unless provider_eligible

      unless valid && provider_eligible
        return render(Payments::CheckoutComponent.new(order: @order, gateways: eligible_gateways,
                                                      default_provider: default_provider, errors: contract.errors),
                      status: :unprocessable_entity)
      end

      if @order.status.in?(Payments::Order::SETTLED_STATUSES)
        contract.errors.add(:base, I18n.t("comp_payments.flash.already_settled"))
        return render(Payments::CheckoutComponent.new(order: @order, gateways: eligible_gateways,
                                                      default_provider: default_provider, errors: contract.errors),
                      status: :unprocessable_entity)
      end

      begin
        result = Payments::Activities::Charge.call(
          customer:      @customer,
          order:         @order,
          provider:      provider,
          request:       request,
          openid:        params[:openid],
          save_card:     save_card_requested?,
          user:          current_tenant_user,
          handoff_token: handoff_token_for_charge
        )
      rescue Payments::Errors::OrderSettled
        contract.errors.add(:base, I18n.t("comp_payments.flash.already_settled"))
        return render(Payments::CheckoutComponent.new(order: @order, gateways: eligible_gateways,
                                                      default_provider: default_provider, errors: contract.errors),
                      status: :unprocessable_entity)
      rescue Payments::Errors::OrderExpired
        contract.errors.add(:base, I18n.t("comp_payments.flash.already_expired"))
        return render(Payments::CheckoutComponent.new(order: @order, gateways: eligible_gateways,
                                                      default_provider: default_provider, errors: contract.errors),
                      status: :unprocessable_entity)
      rescue Payments::Errors::OrderInFlight
        contract.errors.add(:base, I18n.t("comp_payments.flash.provider_switch_blocked"))
        return render(Payments::CheckoutComponent.new(order: @order, gateways: eligible_gateways,
                                                      default_provider: default_provider, errors: contract.errors),
                      status: :unprocessable_entity)
      rescue Payments::Errors::Error
        contract.errors.add(:base, I18n.t("comp_payments.flash.charge_failed"))
        return render(Payments::CheckoutComponent.new(order: @order, gateways: eligible_gateways,
                                                      default_provider: default_provider, errors: contract.errors),
                      status: :unprocessable_entity)
      end

      flow = result[:flow]

      if flow == :card
        render Payments::WidgetCheckoutComponent.new(
          order:           @order,
          payment:         result[:payment],
          gateway:         Payments::Gateways.for(provider),
          result_url:      payment_result_url(@customer.id, payment_id: result[:payment].out_trade_no),
          status_url:      payment_status_url(@customer.id, id: result[:payment].out_trade_no)
        )
      else
        component_class = FLOW_COMPONENTS.fetch(flow)
        render component_class.new(payment: result[:payment])
      end
    end

    def status
      # Look up by `out_trade_no` rather than the integer primary key.
      # `id` is sequential and trivially enumerable; an unauthenticated
      # caller could otherwise iterate ids to discover/poll arbitrary
      # payments in the tenant (and trigger billable PSP queries).
      # `out_trade_no` is a high-entropy provider-side identifier.
      lookup = params[:id].to_s
      payment = Payments::Payment.find_by(customer_id: @customer.id, out_trade_no: lookup)
      payment ||= Payments::Payment.find_by(customer_id: @customer.id, id: lookup) if lookup.match?(/\A\d+\z/) && current_user&.platform_owner?

      return head :not_found unless payment

      if payment.status == "pending"
        begin
          Payments::Activities::Query.call(customer: @customer, payment: payment)
        rescue Payments::Errors::Error
          # Leave the locally known status; the shopper poll must not 500.
        end
      end
      render json: { status: payment.reload.status }
    end

    private

    # The active payment handoff's per-invocation token, stamped onto the
    # Payment at charge time so completion can be bound to this exact invocation.
    # nil for a direct (non-handoff) checkout or a cross-tenant session.
    def handoff_token_for_charge
      invocation = current_invocation
      invocation[:token] if invocation && Payments::HandoffCompletion.order_matches?(
        customer: @customer, order: @order, invocation: invocation
      )
    rescue FeatureModules::CrossTenantViolation
      nil
    end

    def eligible_gateways
      @eligible_gateways ||= Payments::EligibleGateways.for(@customer, currency: @order&.currency)
    end

    def default_provider
      stored = Payments::DefaultGateway.provider_for(@customer.id)
      keys   = eligible_gateways.map { |gw| gw.key.to_s }
      keys.include?(stored) ? stored : keys.first
    end

    def set_customer
      @customer = Customer.find(params[:customer_id])
      Current.customer = @customer
    end

    def require_payments_module!
      return if FeatureModules::Module.enabled?(key: "payment", customer_id: @customer.id)

      head :not_found
    end

    # Whether the gateway has :tokenized_cards capability and the shopper is
    # an authenticated member of this tenant. Both conditions must be true.
    # This drives the "Save this card" checkbox in CardCheckoutComponent.
    def allow_save_card?
      return false unless current_user.present?
      return false unless current_user.member?
      return false unless current_user.customer_id == @customer.id

      provider = @resolved_provider.presence || params[:provider].presence || default_provider
      return false if provider.blank?

      gateway_klass = Payments::Gateways.for(provider)
      gateway_klass.capabilities.include?(:tokenized_cards)
    rescue ArgumentError
      false
    end

    # True when allow_save_card? is enabled AND the shopper has checked the box.
    def save_card_requested?
      allow_save_card? && params[:save_card].in?([ "1", "true", true ])
    end

    # One order per invocation: external_ref is derived from the invocation
    # token (stable across replays of the SAME invocation, unique across
    # different ones), so double-submit / back+retry reuse the row while two
    # distinct handoffs never collide. The block runs on insert only, so the
    # original order's monetary fields stay authoritative and immutable.
    # find_or_create_by! finds-first; the rescue absorbs the narrow window where
    # two brand-new concurrent requests race the unique index rather than
    # surfacing an uncaught RecordNotUnique (500) on this public endpoint.
    def build_order_from(invocation)
      input  = invocation.fetch(:input)
      ref    = Payments::HandoffCompletion.order_reference(invocation[:token])
      orders = Payments::Order.for_current_customer
      orders.find_or_create_by!(external_ref: ref) do |order|
        order.amount = Payments::Money.normalize(input[:amount], input[:currency])
        order.currency     = input[:currency].to_s.upcase
        order.subject      = input[:subject]
        order.body         = input[:body]
        order.expires_at   = input[:expires_at]
        order.metadata     = input[:metadata] || {}
        order.on_success   = invocation[:on_success].to_h
      end
    rescue ActiveRecord::RecordNotUnique
      orders.find_by!(external_ref: ref)
    end

    def set_or_build_order
      ref = params[:ref] || params[:external_ref]
      return render(plain: t("comp_payments.flash.missing_ref"), status: :bad_request) if ref.blank?

      # Orders MUST be pre-created by an authenticated server-side flow
      # (e.g. subscription charging, cart-to-order). Accepting amount /
      # subject / body from this anonymous request would allow trivial
      # price tampering: any visitor could craft a checkout with their
      # chosen amount, then complete payment at that amount.
      @order = Payments::Order.for_current_customer.find_by(external_ref: ref)
      return render(plain: t("comp_payments.flash.order_not_found"), status: :not_found) unless @order

      invocation = current_invocation
      if invocation && invocation[:module_key] == "payment" &&
         !Payments::HandoffCompletion.order_matches?(customer: @customer, order: @order, invocation: invocation)
        head :forbidden
      end
    rescue FeatureModules::CrossTenantViolation
      head :forbidden
    end

    # Alipay in-app browsers parse as Safari 16 / Chrome 69–105, which
    # ApplicationController's allow_browser :modern would 406. Same seam as
    # Oauth::BearerAuthenticatable — the anonymous lambda cannot be skipped.
    def allow_browser(versions:, block:)
    end
  end
end
