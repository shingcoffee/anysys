# frozen_string_literal: true

# Explicitly preloaded by the SMS UI browser server/fixture runner only.
# RSpec uses TEST_DATABASE; the development-only SKIP_AUTH browser server uses
# DATABASE_URL pointing at that same disposable file after RSpec has finished.
require_relative "../../../config/application"

expected = File.expand_path(ENV.fetch("TEST_DATABASE"))
abort "SMS UI E2E opt-in required" unless ENV["SMS_CAMPAIGN_UI_E2E"] == "1"
abort "SMS UI E2E requires its disposable database" unless expected == "/tmp/opencode/sms-campaign-ui20261013.sqlite3"
ActiveRecord::Base.configurations = Rails.application.config.database_configuration
configuration = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary")
abort "SMS UI E2E database mismatch" unless configuration.adapter == "sqlite3" && File.expand_path(configuration.database, Rails.root) == expected
abort "SMS UI E2E requires development or test" unless Rails.env.development? || Rails.env.test?

Rails.application.config.active_job.queue_adapter = :test
Rails.application.config.to_prepare do
  # Local credential readiness and provider codes are real. No UI preview/save/
  # launch/cancel request is permitted to make an external SMS attempt.
  stub = Module.new do
    def send_message(*)
      raise "SMS UI E2E unexpectedly attempted provider delivery"
    end
  end
  Sms::Adapters::Aliyun.prepend(stub)
end
