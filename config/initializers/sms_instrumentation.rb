# frozen_string_literal: true

# Attach the SMS send log subscriber once per process.
Rails.application.config.after_initialize do
  Sms::Instrumentation.subscribe!
end
