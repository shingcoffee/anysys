# frozen_string_literal: true

module Payments
  # Public-by-design controller: shoppers returning from WeChat/Alipay do not
  # have a user account, so the payment result page is reachable without
  # authentication. Tenant scoping is pinned explicitly at the call site below
  # so the lookup cannot drift across customers via the URL.
  class ResultsController < ApplicationController
    # Reads the page → payment handoff invocation from the session (tenant-checked).
    include FeatureModules::InvocationContext
    include ComponentPageRendering

    # See CheckoutsController: shopper-facing pages use a dedicated minimal
    # storefront layout instead of the tenant dashboard shell.
    layout "payments_storefront"

    skip_before_action :authenticate_user!, raise: false

    before_action :set_customer

    # Terminal page for every checkout flow (QR poll, card widget, JSAPI, H5 all
    # land here once the payment resolves). When the shopper arrived through a
    # page → payment handoff and the payment succeeded, complete the invocation
    # and return them to the page author's configured exit_target. Otherwise
    # render the standalone result page.
    def show
      lookup = params[:payment_id].to_s
      # Same identifier as the public status poll: out_trade_no is
      # high-entropy. Sequential integer PKs are enumerable on this
      # unauthenticated page and leak external_ref / status.
      @payment = Payments::Payment.find_by(customer_id: @customer.id, out_trade_no: lookup)
      @payment ||= Payments::Payment.find_by(customer_id: @customer.id, id: lookup) if lookup.match?(/\A\d+\z/) && current_user&.platform_owner?
      raise ActiveRecord::RecordNotFound unless @payment

      refresh_pending_payment!

      completion = Payments::HandoffCompletion.call(
        session: session, customer: @customer, payment: @payment
      )
      if completion
        completion[:flash].each { |key, value| flash[key] = value }
        # A "url"-kind exit_target legitimately points at another host (e.g. a
        # vendor's own confirmation page). It is admin-configured and scheme-
        # restricted to http/https by ExitResolver,
        # so opt out of Rails' same-host redirect guard here.
        return redirect_to completion[:redirect_to], allow_other_host: true
      end

      render Payments::ResultComponent.new(payment: @payment, return_path: fallback_return_path)
    end

    private

    # Where the result page's "Return" CTA points when the handoff was not
    # auto-completed (direct payment, non-success, or already-cleared session).
    # Honors the page author's exit_target when the invocation is still present.
    # Shoppers land here from JSAPI/H5/QR without a webhook having arrived
    # yet. Query the PSP so a completed capture is not shown as failure.
    def refresh_pending_payment!
      return unless @payment.status.in?(%w[pending created])

      Payments::Activities::Query.call(customer: @customer, payment: @payment)
      @payment.reload
    rescue Payments::Errors::Error
      # Leave the stored status; the result page still renders.
    end

    def fallback_return_path
      invocation = current_invocation
      FeatureModules::ExitResolver.call(
        customer:            @customer,
        module_key:          "payment",
        session_exit_target: invocation&.dig(:exit_target),
        audience:            invocation&.dig(:audience)
      )
    rescue FeatureModules::CrossTenantViolation
      root_path
    end

    def set_customer
      @customer = Customer.find(params[:customer_id])
      Current.customer = @customer
    end

    # See CheckoutsController#allow_browser — Alipay webviews are not "modern".
    def allow_browser(versions:, block:)
    end
  end
end
