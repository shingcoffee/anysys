# frozen_string_literal: true

module Sms
  # Common HTTP setting layered over the vendor credential activity. Both the
  # common setting and vendor assignment persist in the same transaction.
  class PlatformCredentialSave
    def self.call(record:, params:)
      attrs = params.to_h.symbolize_keys
      if attrs.key?(:sender_rate_per_second)
        raw = attrs.delete(:sender_rate_per_second)
        number = begin
          Float(raw)
        rescue ArgumentError, TypeError
          nil
        end
        unless number&.finite? && number.positive? && number <= 1
          record.config = (record.config || {}).merge("sender_rate_per_second" => raw)
          record.errors.add(:sender_rate_per_second, I18n.t("sms_campaign_http.errors.invalid_sender_rate"))
          return Activities::SaveCredential::Result.new(success?: false, model: record, errors: record.errors.full_messages)
        end
        record.config = (record.config || {}).merge("sender_rate_per_second" => number)
      end
      Activities::SaveCredential.call(record: record, params: attrs)
    end
  end
end
