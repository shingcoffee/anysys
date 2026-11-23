# frozen_string_literal: true

require "rack/attack"

module Captcha
  # Front-of-app throttle. Uses Rack::Attack's cache counter (mature limiter)
  # with dynamic per-URL limits. Over-limit requests are redirected to the
  # captcha challenge; the target page is not rendered.
  class RackGate
    def initialize(app)
      @app = app
    end

    def call(env)
      gate_response(env) || @app.call(env)
    end

    private

    # Fail open only for captcha processing. Downstream controller exceptions
    # (including CSRF/auth failures) must propagate without retrying the app.
    def gate_response(env)
      return if env["captcha.replay"]

      req = ActionDispatch::Request.new(env)
      if (passage = Captcha::RequestPassage.take!(req))
        env["captcha.result"] = passage["captcha_result"]
        return if passage["allow"]
      end
      # `request.path` prepends SCRIPT_NAME; throttle templates are written
      # against the router path (`/auth/sign_in`, `/:cid/page/:id`, …).
      path = req.path_info
      return if Captcha::UrlMatcher.skip?(path)
      return if one_click_unsubscribe?(req)

      rule = Captcha::UrlMatcher.for_request(req)
      return unless rule
      return if rule.skipped?

      ip = client_ip(req)
      return if Captcha::Grant.active?(ip: ip, pattern: rule.pattern)

      if rule.every_hit
        return challenge(req, rule) unless captcha_unavailable_fail_open?(rule)
      else
        count = increment(ip, rule)
        if count > rule.limit_count.to_i
          return challenge(req, rule) unless captcha_unavailable_fail_open?(rule)
        end
      end

      nil
    rescue ActionController::InvalidAuthenticityToken
      raise
    rescue StandardError => e
      Rails.logger.warn("[captcha.gate] fail-open: #{e.class}: #{e.message}")
      nil
    end

    def client_ip(request)
      (request.remote_ip.presence || request.ip).to_s
    end

    def increment(ip, rule)
      period = [rule.period_seconds.to_i, 1].max
      Captcha::Grant.mark_window(ip: ip, pattern: rule.pattern, period: period)
      Rack::Attack.cache.count("captcha:#{rule.pattern}:#{ip}", period)
    end

    def one_click_unsubscribe?(request)
      return false unless request.post?
      return false unless request.path_info.start_with?("/unsubscribe/")

      request.get_header("HTTP_LIST_UNSUBSCRIBE").to_s.include?("One-Click") ||
        request.POST["List-Unsubscribe"] == "One-Click"
    rescue StandardError
      false
    end

    def captcha_unavailable_fail_open?(_rule)
      # No configured provider → Verify would return :disabled. Challenging
      # anyway bricks fail-closed surfaces (sign-in) and, if the interstitial
      # minted a Grant, would skip captcha after the vendor is turned on.
      Captcha::ProviderSettings.active.nil?
    end

    def challenge(request, rule)
      snapshot_token = nil
      if request.post? || request.patch? || request.put?
        capture = Captcha::RequestSnapshot.capture(request)
        snapshot_token = capture.token unless capture.oversize
      end

      location = challenge_location(request)
      headers = { "Content-Type" => "text/html; charset=utf-8", "Location" => location }
      if snapshot_token.present?
        Rack::Utils.set_cookie_header!(
          headers,
          Captcha::RequestSnapshot::COOKIE,
          Captcha::RequestSnapshot.cookie_header(snapshot_token, script_name: request.script_name).merge(secure: request.ssl?)
        )
      end
      [302, headers, []]
    end

    def challenge_location(request)
      return_to = "#{request.path}#{request.query_string.present? ? "?#{request.query_string}" : ""}"
      "#{request.script_name}/captcha/challenge?#{Rack::Utils.build_query(return_to: return_to)}"
    end
  end
end
