# frozen_string_literal: true

require "time"

module Sms
  # Shared normalized receipt primitives. An invalid supplied recipient remains
  # invalid rather than disappearing into nil (which means "not supplied").
  module ReceiptDetails
    def self.phone(value)
      return if value.nil? || value == ""

      PhoneNumber.normalize(value) || value
    end

    def self.segments(value)
      string = value.to_s
      string.to_i if string.match?(/\A[1-9][0-9]{0,5}\z/)
    end

    def self.time(value, zone: nil)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return unless value.is_a?(String) && value.present?

      if zone
        return unless value.match?(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\z/)

        Time.find_zone!(zone).strptime(value, "%Y-%m-%d %H:%M:%S")
      else
        # Do not invent a zone for carrier RawDlrDoneDate (YYMMDDhhmm); it
        # remains in raw. REST DateUpdated is RFC 2822/GMT; explicit ISO is OK.
        return unless value.match?(/(?:Z|[+-]\d{2}:?\d{2}|GMT|UTC)\z/i)

        Time.iso8601(value)
      end
    rescue ArgumentError
      begin
        Time.rfc2822(value) unless zone
      rescue ArgumentError
        nil
      end
    end
  end
end
