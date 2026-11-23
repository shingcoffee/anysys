# frozen_string_literal: true

module Sms
  module Admin
    class CampaignReportComponent < BaseComponent
      MAIN_METRICS = %i[matched_count eligible_at_start_count attempted_count delivered_count].freeze
      OTHER_METRICS = %i[pending_count admitted_count api_accepted_count failed_count unknown_count queued_count suppressed_count expired_count skipped_count cancelled_count].freeze

      def initialize(campaign:, report:, records:, columns:, pagination:, filters:)
        @campaign, @report, @records, @columns, @pagination, @filters = campaign, report || {}, records, columns, pagination, filters || {}
      end

      def report_filters
        [{ key: :status, label: t("sms_campaign_http.csv.recipient_status"), options: %w[pending admitted skipped cancelled].map { |s| [label_text(:statuses, s), s] } },
         { key: :message_status, label: t("sms_campaign_http.csv.message_status"), options: %w[queued sent delivered failed unknown suppressed expired].map { |s| [label_text(:statuses, s), s] } },
         { key: :skip_reason, label: t("admin_modules.sms.opt_outs.reason"), options: (@report.fetch(:skip_counts, {}).keys + [@filters[:skip_reason]].compact).uniq.map { |code| [reason_label(code), code] } }]
      end

      def display_columns
        @columns.map do |column|
          case column[:key]
          when :name
            column.merge(cell: ->(r) { r.contact_snapshot["name"].presence || r.phone_e164 })
          when :status
            column.merge(badge: ->(r) { { label: label_text(:statuses, r.status), variant: STATUS_TONES.fetch(r.status, :default) } })
          when :message_status
            column.merge(type: :badge, badge: ->(r) { r.message ? { label: label_text(:statuses, r.message.status), variant: STATUS_TONES.fetch(r.message.status, :default) } : nil })
          when :skip_reason
            column.merge(cell: ->(r) { r.skip_reason ? reason_label(r.skip_reason) : t("common.labels.none") })
          else
            column
          end
        end + [
          { key: :dispatch_started_at, label: ui("report.attempted_at"), type: :datetime, sortable: false, cell: ->(r) { r.message&.dispatch_started_at } },
          { key: :delivered_at, label: t("sms_campaign_http.csv.delivered_at"), type: :datetime, sortable: false, cell: ->(r) { r.message&.delivered_at } },
          { key: :deferral_reason, label: ui("report.current_delay"), sortable: false, cell: ->(r) { r.deferral_reason ? reason_label(r.deferral_reason) : t("common.labels.none") } }
        ]
      end
    end
  end
end
