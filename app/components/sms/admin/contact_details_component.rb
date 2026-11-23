# frozen_string_literal: true

module Sms
  module Admin
    class ContactDetailsComponent < BaseComponent
      attr_reader :contact

      def initialize(contact:, consent_events:, eligibility:, consent_form_values:, errors:)
        @contact, @consent_events, @eligibility = contact, consent_events, eligibility
        @consent_form_values, @errors = consent_form_values, errors || {}
      end

      def history_columns
        [
          { key: :created_at, label: ui("contacts.recorded_at"), type: :datetime, sortable: false },
          { key: :action, label: t("common.labels.action"), type: :badge, sortable: false, badge: ->(e) { { label: label_text(:statuses, e.action), variant: STATUS_TONES.fetch(e.action, :default) } } },
          { key: :phone_e164, label: t("sms_audience.fields.phone_e164"), sortable: false },
          { key: :occurred_at, label: ui("fields.occurred_at"), type: :datetime, sortable: false },
          { key: :source, label: t("sms_audience.fields.source_kind"), sortable: false, cell: ->(e) { label_text(:sources, e.source) } },
          { key: :actor_user_id, label: ui("contacts.actor"), sortable: false },
          { key: :evidence, label: ui("contacts.evidence"), sortable: false, cell: ->(e) { tag.dl { safe_join(e.evidence.slice("reference", "statement", "notes").map { |k, v| fact(label_text(:fields, k), v) }) } } }
        ]
      end
    end
  end
end
