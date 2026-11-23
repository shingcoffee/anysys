# frozen_string_literal: true

module Billing
  module Admin
    # Urgent collection / 3DS recovery actions for an unpaid customer invoice.
    class PaymentCollectionBannerComponent < ApplicationComponent
      include Presentation

      attr_reader :invoice, :collection, :payment_action, :customer_id, :collection_state, :collection_tone,
                  :recovery_data, :retry_path, :result_path, :one_time_payment_path

      def initialize(invoice:, collection:, customer_id:, collection_state:, collection_tone:, stripe_recovery:,
                     recovery_data:, show_retry:, retry_path:, result_path:, payment_action: nil,
                     show_one_time_payment: false, one_time_payment_path: nil)
        @invoice = invoice
        @collection = collection
        @payment_action = payment_action
        @customer_id = customer_id
        @collection_state = collection_state
        @collection_tone = collection_tone
        @stripe_recovery = stripe_recovery
        @recovery_data = recovery_data
        @show_retry = show_retry
        @retry_path = retry_path
        @result_path = result_path
        @show_one_time_payment = show_one_time_payment
        @one_time_payment_path = one_time_payment_path
      end

      def render?
        !(invoice.status.to_s == "paid" && fact(invoice, :settlement_review_code).blank?)
      end

      def stripe_recovery? = @stripe_recovery
      def show_retry? = @show_retry
      def show_one_time_payment? = @show_one_time_payment

      def tone_icon = collection_tone.first
      def tone_classes = collection_tone.last

      def banner_surface_classes
        case collection_state.to_s
        when "exhausted" then "border-danger/30 bg-danger-subtle"
        when "requires_action", "blocked", "reconciliation_required" then "border-warning/30 bg-warning-subtle"
        when "settled" then "border-success/30 bg-success-subtle"
        when "ready", "manual", "pending", "retry_wait" then "border-info/30 bg-info-subtle"
        else "border-border-subtle bg-canvas-elevated"
        end
      end

      def show_next_attempt?
        fact(collection, :next_attempt_at).present? && collection_state.to_s.in?(%w[ready retry_wait blocked])
      end
    end
  end
end
