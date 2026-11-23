# frozen_string_literal: true

# Attach the auth audit-log subscriber once per process.
Rails.application.config.after_initialize do
  Authentication::Instrumentation.subscribe!
end
