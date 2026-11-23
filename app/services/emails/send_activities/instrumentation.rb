# frozen_string_literal: true

module Emails
  module SendActivities
    # Consumes the `email_send_activity.lifecycle` notification (started / completed /
    # failed) and turns it into a structured log line — campaign-level
    # observability to match the per-message `email.send` instrumentation.
    class Instrumentation
      WARN_EVENTS = %w[failed].freeze

      def self.subscribe!
        ActiveSupport::Notifications.subscribe("email_send_activity.lifecycle") do |*args|
          new.log(ActiveSupport::Notifications::Event.new(*args))
        end
      end

      def log(event)
        p = event.payload
        message = "[email_send_activity] #{p[:event]} campaign=#{p[:send_activity_id]} recipients=#{p[:recipients] || '-'}"
        WARN_EVENTS.include?(p[:event].to_s) ? Rails.logger.warn(message) : Rails.logger.info(message)
      end
    end
  end
end
