# frozen_string_literal: true

module Email
  # Consumes the `email.send` notification emitted by the delivery pipeline and
  # turns it into a structured log line (send outcome rates by provider). Plain
  # Notifications subscriber (namespace-first event name "email.send").
  class Instrumentation
    WARN_OUTCOMES = %w[failed].freeze

    def self.subscribe!
      ActiveSupport::Notifications.subscribe("email.send") do |*args|
        new.log(ActiveSupport::Notifications::Event.new(*args))
      end
    end

    def log(event)
      p = event.payload
      message = "[email] send outcome=#{p[:outcome]} provider=#{p[:provider] || '-'}"
      WARN_OUTCOMES.include?(p[:outcome].to_s) ? Rails.logger.warn(message) : Rails.logger.info(message)
    end
  end
end
