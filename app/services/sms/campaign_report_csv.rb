# frozen_string_literal: true

require "csv"

module Sms
  class CampaignReportCsv
    KEYS = %i[campaign_id recipient_id contact_id name phone_e164 recipient_status skip_reason message_id message_status dispatch_started_at sent_at delivered_at expires_at failure_code provider_segments].freeze

    def self.call(scope:, customer:, locale: I18n.locale)
      Enumerator.new do |output|
        Current.set(customer: customer) do
          I18n.with_locale(locale) do
            output << CSV.generate_line(KEYS.map { |key| I18n.t("sms_campaign_http.csv.#{key}") })
            scope.reorder(:id).find_each(batch_size: 100) do |recipient|
              message = recipient.message
              values = [recipient.campaign_id, recipient.id, recipient.contact_id, recipient.contact_snapshot["name"],
                        recipient.phone_e164, recipient.status, recipient.skip_reason, recipient.message_id, message&.status,
                        message&.dispatch_started_at, message&.sent_at, message&.delivered_at, message&.expires_at,
                        message&.failure_code, message&.metadata&.[]("provider_segments")]
              output << CSV.generate_line(values.map { |value| safe_cell(value) })
            end
          end
        end
      end
    end

    def self.safe_cell(value)
      return value.iso8601 if value.respond_to?(:iso8601)
      return value if value.is_a?(Numeric) || value.nil?

      text = value.to_s
      text.match?(/\A[\s\uFEFF]*[=+\-@]|\A[\t\r\n]/) ? "'#{text}" : text
    end
    private_class_method :safe_cell
  end
end
