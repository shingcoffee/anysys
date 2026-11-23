# frozen_string_literal: true

require "digest"

module Payments
  # Bridges a resolved payment back to the page → payment handoff that launched
  # it. When a shopper reached checkout through a FeatureModules handoff (a
  # session invocation with module_key "payment") AND the payment succeeded,
  # this completes the invocation via FeatureModules::Complete — validating the
  # module output contract, resolving the page author's configured exit_target,
  # writing the completion audit log, and clearing the session.
  #
  # Returns the { redirect_to:, flash: } hash from FeatureModules::Complete when
  # the handoff was completed, or nil when there is nothing to complete:
  #   - the payment has not succeeded (leave the shopper on the result page),
  #   - no invocation is in the session (a direct/non-handoff payment),
  #   - the active invocation belongs to a different module,
  #   - the payment being viewed was NOT charged within this invocation
  #     (per-invocation token mismatch — prevents replaying an unrelated
  #     succeeded payment, guessed by its enumerable id, to complete a
  #     still-unpaid handoff),
  #   - the session was already cleared (idempotent on reload), or
  #   - the invocation belongs to another tenant.
  # A nil return means the caller should render the standalone result page.
  class HandoffCompletion
    MODULE_KEY = "payment"

    def self.call(session:, customer:, payment:)
      new(session: session, customer: customer, payment: payment).call
    end

    def self.order_reference(token)
      "ORD-#{Digest::SHA256.hexdigest(token.to_s)[0, 12].upcase}"
    end

    # Shared by charge and completion: a token alone must never authorize an
    # unrelated cheaper order or a changed monetary identity.
    def self.order_matches?(customer:, order:, invocation:)
      return false unless invocation[:module_key] == MODULE_KEY && invocation[:token].present?
      return false unless invocation[:customer_id].to_s == customer.id.to_s && order.customer_id == customer.id
      return false unless order.external_ref == order_reference(invocation[:token])

      input = invocation[:input] || {}
      currency = input[:currency].to_s.upcase
      amount = Payments::Money.normalize(input[:amount], currency)
      amount.positive? && order.currency == currency && order.amount == amount
    rescue ArgumentError, TypeError
      false
    end

    def initialize(session:, customer:, payment:)
      @session  = session
      @customer = customer
      @payment  = payment
    end

    def call
      return nil unless @payment.status == "succeeded"

      invocation = active_payment_invocation
      return nil unless invocation
      return nil unless payment_belongs_to?(invocation)

      FeatureModules::Complete.call(
        session:    @session,
        customer:   @customer,
        module_key: MODULE_KEY,
        output:     module_output
      )
    rescue FeatureModules::CrossTenantViolation, FeatureModules::OutputContractViolation => e
      # The shopper still sees a valid result page; the handoff simply isn't
      # auto-completed. Surfacing a 500 here would be worse than a manual return.
      Rails.logger.warn("[payments.handoff_completion] #{e.class}: #{e.message}")
      nil
    end

    private

    def active_payment_invocation
      invocation = FeatureModules::Invocation.current(@session)
      invocation if invocation.present? && invocation[:module_key] == MODULE_KEY
    rescue FeatureModules::CrossTenantViolation
      nil
    end

    # The invocation is fulfilled ONLY by the payment charged within it. The
    # per-invocation token minted at begin! and stamped onto the Payment at
    # charge time must match. This scopes completion to the exact invocation, so
    # a shopper cannot point the result URL at some other succeeded payment
    # (guessed by its enumerable id) to complete their own unpaid handoff — the
    # token, held only in that session, would not match.
    def payment_belongs_to?(invocation)
      token = invocation[:token].to_s
      token.present? && token == @payment.handoff_token.to_s &&
        @payment.customer_id == @customer.id && @payment.amount == @payment.payment_order.amount &&
        self.class.order_matches?(customer: @customer, order: @payment.payment_order, invocation: invocation)
    end

    # Shape defined by FeatureModules::Payment::Registration.output_contract.
    def module_output
      {
        payment_reference: @payment.out_trade_no,
        status:            "succeeded",
        paid_at:           @payment.paid_at&.iso8601
      }
    end
  end
end
