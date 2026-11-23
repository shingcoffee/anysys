# frozen_string_literal: true

module Captcha
  # Warden can throw out of the controller dispatch and return its own redirect.
  # Annotate outside its catch, but inside session middleware so result-only
  # redirect receipts are persisted before the session cookie is committed.
  class ResponseMarker
    def initialize(app)
      @app = app
    end

    def call(env)
      response = @app.call(env)
      return response unless env.key?("captcha.result")

      status, headers, body = response
      headers = Rack::Headers[headers]
      headers["X-Captcha-Result"] = env["captcha.result"] ? "true" : "false"
      headers["Cache-Control"] = "no-store"
      if (300..399).cover?(status)
        Captcha::RequestPassage.forward(request: ActionDispatch::Request.new(env),
                                       location: headers["Location"], captcha_result: env["captcha.result"])
      end
      [status, headers, body]
    end
  end
end
