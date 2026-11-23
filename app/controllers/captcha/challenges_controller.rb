# frozen_string_literal: true

module Captcha
  # Public captcha interstitial. No auth. After a pass, grants access and
  # either replays the original POST or redirects to the original GET.
  class ChallengesController < ApplicationController
    layout "auth"
    skip_before_action :enforce_mfa!
    before_action :load_challenge
    after_action :deny_referrer

    def show
      redirect_to @return_to and return if Captcha::Grant.active?(ip: request.remote_ip, pattern: @rule.pattern)
    end

    def create
      context = Captcha::VerificationContext.new(
        verify_param: params[:captcha_verify_param].to_s,
        remoteip:     request.remote_ip,
        user_agent:   request.user_agent,
        hostname:     request.host,
        action:       :access_challenge
      )
      result = Captcha::Activities::Verify.call(context: context)
      response.set_header("X-Captcha-Result", result.passed? ? "true" : "false")

      if result.passed?
        complete_success(grant: true)
      elsif result.disabled?
        # Unconfigured captcha must never block, including fail-closed auth
        # surfaces — Verify degrades to :disabled so a missing provider cannot
        # DoS sign-in. Do not mint a Grant; the gate should not have challenged.
        complete_success(grant: false)
      elsif result.blocked_hard? || @fail_closed || result.fail_policy.to_s == "closed"
        @captcha_failed = true
        flash.now[:alert] = I18n.t(
          CaptchaProtectable::REJECTION_KEYS.fetch(result.outcome, CaptchaProtectable::REJECTION_KEYS[:invalid])
        )
        render :show, status: :unprocessable_content
      else
        # Fail-open (vendor unreachable / misconfigured): let this request
        # through, but do not skip later hits after the vendor recovers.
        complete_success(grant: false)
      end
    end

    private

    def load_challenge
      unless Captcha::ReturnTo.safe?(params[:return_to], request: request)
        raise ActionController::RoutingError, "Not Found"
      end

      @return_to = Captcha::ReturnTo.path_and_query(params[:return_to], request: request)
      @rule      = Captcha::UrlMatcher.for_path(URI.parse(@return_to).path, request: request)
      raise ActionController::RoutingError, "Not Found" unless @rule

      settings = Captcha::ProviderSettings.active
      @fail_closed = @rule.fail_closed || settings&.fail_closed?
      @configured  = settings.present?
    end

    def complete_success(grant: true)
      if grant
        Captcha::Grant.store(
          ip: request.remote_ip,
          pattern: @rule.pattern,
          ttl: Captcha::Grant.ttl_for(@rule, ip: request.remote_ip)
        )
      end
      replay_payload = Captcha::RequestSnapshot.take!(
        cookies[Captcha::RequestSnapshot::COOKIE],
        request: request,
        path: URI.parse(@return_to).path,
        query: URI.parse(@return_to).query.to_s
      )
      cookies.delete(Captcha::RequestSnapshot::COOKIE,
                     path: Captcha::RequestSnapshot.cookie_path(script_name: request.script_name))
      if replay_payload
        status, headers, body = Captcha::RequestReplayer.call(
          env: request.env,
          payload: replay_payload
        )
        self.status = status
        headers.each { |key, value| response.set_header(key, value) if key.present? && value.present? }
        response.set_header("X-Captcha-Result", grant ? "true" : "false")
        if (300..399).cover?(status)
          Captcha::RequestPassage.forward(request: request, location: headers["Location"] || headers["location"],
                                         captcha_result: grant)
        end
        self.response_body = body
      else
        Captcha::RequestPassage.store(request: request, return_to: @return_to,
                                     allow: !grant, captcha_result: grant)
        redirect_to @return_to
      end
    end

    def deny_referrer
      # no-referrer can produce Origin: null on the same-origin form POST.
      response.headers["Referrer-Policy"] = "same-origin"
      response.headers["Cache-Control"] = "no-store"
    end

    # Rails registers allow_browser as an anonymous callback. Embedded payment
    # browsers must be able to complete this public interstitial.
    def allow_browser(versions:, block:)
    end
  end
end
