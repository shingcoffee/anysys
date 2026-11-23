# frozen_string_literal: true

# Attach the email-campaign lifecycle log subscriber once per process.
Rails.application.config.after_initialize do
  Emails::SendActivities::Instrumentation.subscribe!
end
