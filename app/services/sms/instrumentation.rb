# frozen_string_literal: true

module Sms
  # Consumes the `sms.send` notification emitted by Sms::Activities::Send and
  # turns it into a structured log line (send outcome rates, vendor latency).
  # A plain Notifications subscriber (not a LogSubscriber) matches the
  # namespace-first event name "sms.send".
  class Instrumentation
    WARN_OUTCOMES = %w[failed transport_error].freeze

    def self.subscribe!
      ActiveSupport::Notifications.subscribe("sms.send") do |*args|
        new.log(ActiveSupport::Notifications::Event.new(*args))
      end
    end

    def log(event)
      p = event.payload
      duration = p[:duration] ? "#{(p[:duration] * 1000).round(1)}ms" : "-"
      message  = "[sms] send outcome=#{p[:outcome]} provider=#{p[:provider] || '-'} duration=#{duration}"

      WARN_OUTCOMES.include?(p[:outcome].to_s) ? Rails.logger.warn(message) : Rails.logger.info(message)
    end
  end
end
