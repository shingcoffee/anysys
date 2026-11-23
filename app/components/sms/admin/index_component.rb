# frozen_string_literal: true

module Sms
  module Admin
    class IndexComponent < BaseComponent
      attr_reader :records, :columns, :pagination, :filters

      def initialize(records:, columns:, pagination:, filters:)
        @records, @columns, @pagination, @filters = records, columns, pagination, filters || {}
      end

      def singular = kind.to_s.singularize
      def filtered? = filters.slice(:q, :status, :consent_status, :source_kind).values.any?(&:present?)

      def table_filters
        case kind
        when :campaigns
          [filter(:status, %w[draft scheduled running completed cancelled failed])]
        when :contacts
          [filter(:consent_status, %w[unknown granted revoked]), filter(:status, %w[active archived]),
           { key: :source_kind, label: t("sms_audience.fields.source_kind"), options: %w[manual entity].map { |s| [label_text(:sources, s), s] } }]
        else
          []
        end
      end

      def filter(key, values)
        heading = key == :status && kind == :campaigns ? t("common.labels.status") : label_text(:fields, key)
        { key: key, label: heading, options: values.map { |s| [label_text(:statuses, s), s] } }
      end

      def display_columns
        columns.map do |column|
          next column unless %i[status consent_status].include?(column[:key])

          column.merge(badge: ->(record) { state = record.public_send(column[:key]); { label: label_text(:statuses, state), variant: STATUS_TONES.fetch(state, :default) } })
        end
      end

      def row_actions(record)
        if kind == :campaigns && record.status != "draft"
          [{ label: ui("campaigns.report"), path: sms_path(:campaign_report, record) }]
        else
          [{ label: kind == :campaigns ? t("admin_modules.emails.send_activities.wizard.steps.review") : t("admin_modules.index.open"), path: sms_path(singular, record) },
           { label: t("common.actions.edit"), path: sms_path("edit_#{singular}", record) }]
        end
      end

      def empty_help
        kind == :contacts ? ui("contacts.no_implied_consent") : ui("#{kind}.empty_help")
      end
    end
  end
end
