# frozen_string_literal: true

require "rack/attack"

# We only use Rack::Attack's cache counter API (see Captcha::RackGate).
# Its own middleware stays off so it does not apply extra throttles.
Rack::Attack.enabled = false

# Middleware classes in app/ are not autoloaded during initializer evaluation.
# This proxy defers the constant lookup until the first request.
class CaptchaRackGateProxy
  def initialize(app)
    @app = app
  end

  def call(env)
    gate.call(env)
  end

  private

  def gate
    @gate ||= Captcha::RackGate.new(@app)
  end
end

Rails.application.config.middleware.use CaptchaRackGateProxy

class CaptchaResponseMarkerProxy
  def initialize(app)
    @app = app
  end

  def call(env)
    @marker ||= Captcha::ResponseMarker.new(@app)
    @marker.call(env)
  end
end

Rails.application.config.middleware.insert_before Warden::Manager, CaptchaResponseMarkerProxy

Rails.application.config.after_initialize do
  Rack::Attack.cache.store = Captcha::ThrottleRegistry.store
end
