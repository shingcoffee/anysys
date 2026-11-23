# frozen_string_literal: true

RubyLLM.configure do |config|
  config.logger = Rails.logger
  config.request_timeout = 60
  config.max_retries = 0
end
