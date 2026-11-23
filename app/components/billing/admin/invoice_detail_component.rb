# frozen_string_literal: true

module Billing
  module Admin
    # Renders a detailed invoice view with line items, subtotal, discount, tax,
    # and total. Designed to be print-friendly via the billing_invoice_controller.js
    # Stimulus controller.
    #
    # Constructor:
    #   invoice:     Billing::Invoice (with line_items eager-loaded)
    #   customer_id: current customer_id for building route helpers
    #   platform:    bool — true shows admin action buttons (mark_paid, void, retry)
    class InvoiceDetailComponent < ApplicationComponent
      include Presentation
      STATUS_BADGE_MAP = {
        "draft"         => :default,
        "open"          => :warning,
        "paid"          => :success,
        "void"          => :default,
        "uncollectible" => :danger
      }.freeze
      COLLECTION_TONES = {
        "settled" => [:check, "bg-success-subtle text-success"],
        "requires_action" => [:alert, "bg-warning-subtle text-warning"],
        "blocked" => [:alert, "bg-warning-subtle text-warning"],
        "exhausted" => [:alert, "bg-danger-subtle text-danger"],
        "reconciliation_required" => [:alert, "bg-warning-subtle text-warning"],
        "ready" => [:clock, "bg-info-subtle text-info"],
        "manual" => [:clock, "bg-info-subtle text-info"],
        "pending" => [:clock, "bg-info-subtle text-info"],
        "retry_wait" => [:clock, "bg-info-subtle text-info"]
      }.freeze
      NEUTRAL_TONE = [:info, "bg-surface-active text-text-secondary"].freeze

      def initialize(invoice:, customer_id:, platform: false, customer_settings: false, download: false,
                     collection: nil, payment_action: nil, form: nil, settlement: {})
        @invoice     = invoice
        @customer_id = customer_id.to_s
        @platform    = platform
        @customer_settings = customer_settings && !platform
        @download = download
        @collection, @payment_action, @form = collection, payment_action, form
        @settlement = settlement || {}
      end

      attr_reader :invoice, :customer_id, :platform, :customer_settings, :download
      attr_reader :collection, :payment_action, :form
      attr_reader :settlement

      def download_path
        helpers.download_admin_settings_billing_invoice_path(platform? ? invoice.customer_id : customer_id, invoice)
      end

      def platform? = platform

      def status_variant
        STATUS_BADGE_MAP.fetch(invoice.status.to_s, :default)
      end

      def status_label
        key = invoice.status.to_s
        if Billing::Invoice::STATUSES.include?(key)
          I18n.t("comp_billing.invoice_table.statuses.#{key}")
        else
          key
        end
      end

      def format_amount(amount_cents, currency = invoice.currency)
        formatted = billing_amount(amount_cents.abs, currency)
        amount_cents.negative? ? "-#{formatted}" : formatted
      end

      def kind_label(kind)
        key = kind.to_s
        if Billing::InvoiceLineItem::KINDS.include?(key)
          I18n.t("comp_billing.invoice_detail.kinds.#{key}")
        else
          key
        end
      end

      def show_mark_paid?
        !download && platform? && invoice.status.in?(%w[open uncollectible]) && fact(collection, :can_mark_paid) == true
      end

      def show_void?
        !download && platform? && invoice.status.in?(%w[draft open uncollectible]) && fact(collection, :can_void) == true
      end

      def show_retry?
        !download && invoice.status.in?(%w[open uncollectible]) &&
          !collection_state.in?(%w[pending requires_action settled stopped reconciliation_required]) && fact(collection, :can_retry) == true
      end

      def show_one_time_payment?
        !download && !platform? && invoice.status.to_s.in?(%w[open uncollectible]) &&
          !collection_state.in?(%w[requires_action settled stopped reconciliation_required]) &&
          fact(collection, :can_pay_one_time) == true
      end

      def one_time_payment_path
        helpers.admin_settings_billing_invoice_one_time_payment_path(customer_id, invoice)
      end

      def show_collection_authorization?
        !download && platform? && invoice.status.in?(%w[open uncollectible]) &&
          !collection_state.in?(%w[pending requires_action settled reconciliation_required]) && fact(collection, :can_authorize_collection) == true
      end

      def mark_paid_path
        helpers.mark_paid_admin_maintenance_platform_billing_invoice_path(customer_id, invoice)
      end

      def void_path
        helpers.void_admin_maintenance_platform_billing_invoice_path(customer_id, invoice)
      end

      def retry_path
        platform? ? helpers.retry_admin_maintenance_platform_billing_invoice_path(customer_id, invoice) : helpers.admin_settings_billing_invoice_payment_path(customer_id, invoice)
      end

      def collection_state
        { "paid" => "settled", "void" => "stopped", "draft" => "draft" }.fetch(invoice.status) do
          fact(collection, :state).presence || fact(invoice, :collection_state).presence || "unavailable"
        end
      end

      def result_path
        platform? ? helpers.admin_maintenance_platform_billing_invoice_path(customer_id, invoice) : helpers.admin_settings_billing_invoice_path(customer_id, invoice)
      end

      def stripe_recovery?
        !download && !platform? && collection_state == "requires_action" && fact(payment_action, :kind).to_s == "stripe_sca"
      end

      def form_record = invoice
      def form_scope = "settlement"

      def collection_tone
        COLLECTION_TONES.fetch(collection_state, NEUTRAL_TONE)
      end

      def date_label(value)
        value.present? ? I18n.l(value.to_date, format: :long) : I18n.t("common.labels.em_dash")
      end

      def collection_mode_label(mode)
        mode.present? ? I18n.t("comp_billing.settings_form.collection_modes.#{mode}") : I18n.t("common.labels.em_dash")
      end

      def customer_name
        invoice.customer.name if invoice.respond_to?(:customer) && invoice.customer.respond_to?(:name)
      end

      def show_operator_panel?
        platform? && !download && (show_mark_paid? || show_retry? || show_collection_authorization?)
      end

      def recovery_data
        {
          controller: "payments--stripe-card",
          "payments--stripe-card-publishable-key-value" => fact(payment_action, :publishable_key),
          "payments--stripe-card-client-secret-value" => fact(payment_action, :client_secret),
          "payments--stripe-card-result-url-value" => result_path,
          "payments--stripe-card-unavailable-text-value" => I18n.t("comp_payments.shared.stripe_unavailable"),
          "payments--stripe-card-unexpected-error-value" => I18n.t("comp_payments.stripe.unexpected_error"),
          "payments--stripe-card-setup-intent-failed-value" => I18n.t("comp_payments.stripe.setup_intent_failed"),
          "payments--stripe-card-missing-client-secret-value" => I18n.t("comp_payments.stripe.missing_client_secret"),
          "payments--stripe-card-missing-payment-method-value" => I18n.t("comp_payments.stripe.missing_payment_method"),
          "payments--stripe-card-server-error-value" => I18n.t("comp_payments.stripe.server_error"),
          "payments--stripe-card-processing-text-value" => I18n.t("comp_payments.stripe.processing")
        }
      end
    end
  end
end
