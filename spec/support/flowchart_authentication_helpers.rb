# frozen_string_literal: true

module FlowchartAuthenticationHelpers
  # Real Warden proxies with the application's Devise serializers and hooks.
  # A fresh proxy represents the next request, forcing session deserialization
  # instead of returning the principal cached by set_user on the first request.
  def warden_request(session_data = {})
    env = Rails.application.env_config.merge(Rack::MockRequest.env_for("https://example.test/"))
    request = ActionDispatch::Request.new(env)
    options = Rails.application.config.session_options
    store = Rails.application.config.session_store.new(nil, options)
    ActionDispatch::Request::Session.create(store, request, options).merge!(session_data)
    manager = Warden::Manager.new(nil)
    manager.config = Devise.warden_config.dup
    env["warden"] = Warden::Proxy.new(env, manager)
    request
  end

  def warden_round_trip(user)
    request = warden_request
    request.env["warden"].set_user(user, scope: :user)
    warden_request(request.session.to_hash.deep_dup)
  end
end
