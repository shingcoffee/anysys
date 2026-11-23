# frozen_string_literal: true

# Attach the captcha verification log subscriber once per process (idempotent
# across dev reloads because after_initialize runs a single time per boot).
Rails.application.config.after_initialize do
  Captcha::Instrumentation.subscribe!
end
