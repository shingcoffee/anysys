# frozen_string_literal: true

RSpec.configure do |config|
  config.before do
    store = Captcha::ThrottleRegistry.store
    store.clear if store.respond_to?(:clear)
    Rack::Attack.cache.store = store if defined?(Rack::Attack)
  end
end
