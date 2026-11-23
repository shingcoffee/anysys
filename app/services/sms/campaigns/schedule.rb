# frozen_string_literal: true

require "tzinfo"

module Sms
  module Campaigns
    class Schedule
      def self.parse(local:, timezone:)
        return nil if local.nil? || local == ""
        return nil unless local.is_a?(String) && local.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/)

        wall = Time.strptime(local, "%Y-%m-%dT%H:%M")
        # strptime's host timezone must never influence a wall-clock input.
        wall = Time.utc(wall.year, wall.month, wall.day, wall.hour, wall.min)
        return nil unless wall.strftime("%Y-%m-%dT%H:%M") == local

        TZInfo::Timezone.get(timezone).local_to_utc(wall)
      rescue ArgumentError, TZInfo::InvalidTimezoneIdentifier, TZInfo::PeriodNotFound, TZInfo::AmbiguousTime
        nil
      end

      def self.valid_zone?(zone)
        zone.is_a?(String) && TZInfo::Timezone.get(zone).present?
      rescue TZInfo::InvalidTimezoneIdentifier
        false
      end
    end
  end
end
