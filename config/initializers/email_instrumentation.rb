# frozen_string_literal: true

# Attach the email send log subscriber once per process.
Rails.application.config.after_initialize do
  Email::Instrumentation.subscribe!
end
