# frozen_string_literal: true

module Authentication
  class SignInLinksController < ApplicationController
    include TenantContext
    include Authentication::IssuesSignInLink
    include Authentication::PermitsUserParams
    include Authentication::TrustedDeviceCookieable
    include Authentication::FinishesSignIn
    include Authentication::NoStore

    layout "auth"

    before_action :redirect_signed_in_user
    # #show is addressed by the sign-in token, so keep its responses out of
    # caches and stop the token's URL leaking through the Referer header.
    before_action :no_store!, only: :show

    # POST /auth/sign_in_link
    def create
      issue_sign_in_link(permitted_user_params(:email)[:email])
    end

    # GET /auth/sign_in_link/check_email
    def check_email
      @email = session[:sign_in_link_email].to_s
      redirect_to(new_user_session_path) and return if @email.blank?
    end

    # GET /auth/sign_in_link?token=…
    #
    # HEAD is answered without touching the token. Mail clients, corporate
    # security proxies, and link scanners probe URLs before a human ever sees
    # them, and a probe must not burn a one-time link.
    #
    # We deliberately stop there instead of rendering an interstitial that
    # POSTs the token. An interstitial only defends against agents that follow
    # GETs — and those are the same agents that would happily submit the
    # form or that render the page with no side effect — while it costs an
    # extra full page plus locale keys, adds a round trip to every sign-in,
    # and breaks the copy-and-paste URL fallback the mail prints for clients
    # that strip buttons. The defences we keep instead are the 15-minute TTL,
    # atomic single-use consumption, and a burnt link failing closed with a
    # "request a new one" prompt.
    def show
      return head(:ok) if request.head?

      consumed = ConsumeSignInLink.call(token: params[:token])
      return reject_link unless consumed.success?

      result = SignInFlow.complete(
        user: consumed.user,
        trusted_device_token: trusted_device_token
      )
      return reject_link(user: consumed.user) unless result.success?

      finish_sign_in(result, remember_me: false)
    end

    private

    # The password flow audits every rejected attempt; this one is just as
    # guessable, so a bad, expired, or replayed token has to leave the same
    # trace. `flow` discriminates it from a password failure in the ledger.
    def reject_link(user: nil)
      Authentication::AuditLog.record(event: :login_failed, user: user,
                                      customer_id: user&.customer_id,
                                      request: request, flow: "sign_in_link")
      redirect_to new_user_session_path, alert: t("auth.flash.sign_in_link.invalid")
    end

    def redirect_signed_in_user
      return unless user_signed_in?

      redirect_to default_signed_in_path_for(current_user)
    end
  end
end
