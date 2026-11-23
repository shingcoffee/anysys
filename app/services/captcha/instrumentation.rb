# frozen_string_literal: true

module Captcha
  # Consumes the `captcha.verify` notification emitted by Captcha::Activities::Verify
  # and turns it into a structured log line. Previously the notification was
  # emitted but had no subscriber; this makes verification observable (outcome
  # rates, vendor latency, score distribution) without coupling the activity to
  # a logging concern.
  #
  # A plain Notifications subscriber (not an ActiveSupport::LogSubscriber) is used
  # deliberately: LogSubscriber binds to "<method>.<namespace>" event names, but
  # the domain event is named "captcha.verify" (namespace-first), so a direct
  # subscribe on that exact name is the correct wiring.
  class Instrumentation
    def self.subscribe!
      ActiveSupport::Notifications.subscribe("captcha.verify") do |*args|
        new.log(ActiveSupport::Notifications::Event.new(*args))
      end
    end

    def log(event)
      p = event.payload
      duration_ms = (p[:duration] ? p[:duration] * 1000 : event.duration).round(1)
      message = "[captcha] verify outcome=#{p[:outcome]} provider=#{p[:provider]} " \
                "http_status=#{p[:http_status] || '-'} score=#{p[:score] || '-'} duration=#{duration_ms}ms"

      p[:outcome] == :success ? Rails.logger.info(message) : Rails.logger.warn(message)
    end
  end
end
