# frozen_string_literal: true

module Billing
  module Admin
    # Customer settings presentation of one invoice (Area b) — the on-screen
    # view and the printable download share this document.
    class CustomerInvoiceDetailComponent < InvoiceDetailComponent
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

      def initialize(**options)
        super(**options, platform: false, customer_settings: true)
      end

      def collection_tone
        COLLECTION_TONES.fetch(collection_state, NEUTRAL_TONE)
      end

      def date_label(value)
        value.present? ? I18n.l(value.to_date, format: :long) : I18n.t("common.labels.em_dash")
      end

      def collection_mode_label(mode)
        mode.present? ? I18n.t("comp_billing.settings_form.collection_modes.#{mode}") : I18n.t("common.labels.em_dash")
      end
    end
  end
end
