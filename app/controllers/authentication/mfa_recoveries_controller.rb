# frozen_string_literal: true

require "ostruct"

module Authentication
  # Public endpoint that lets a member who lost their authenticator request
  # an email link that disables their MFA. Identical responses for hit/miss
  # to prevent email enumeration. Member-only enforcement lives in the
  # operations, NOT here.
  class MfaRecoveriesController < ApplicationController
    include Authentication::EmailFloodThrottled
    include Authentication::NoStore

    layout "auth"

    before_action :throttle_recovery_requests!, only: :create
    prepend_before_action :no_store!, only: :consume

    def new
    end

    def create
      contract = Member::Mfa::Contracts::ResetRequest.new(OpenStruct.new(email: nil))

      if contract.validate(email: params[:email])
        Member::Mfa::Operation::RequestResetLink.call(
          customer_id: current_customer_id, email: params[:email]
        )
      end

      # Always render the same generic page, even on contract failure.
      render :create
    end

    def consume
      return head(:ok) if request.head?
      return render_consume_confirm if request.get?

      result = Member::Mfa::Operation::ConsumeResetLink.call(
        token: params[:token], request: request, actor: current_user
      )

      reset_session
      sign_out(:user) if user_signed_in?

      if result.success?
        redirect_to new_user_session_path,
                    notice: t("authentication.mfa_recovery.consumed")
      else
        redirect_to new_user_session_path,
                    alert:  t("authentication.mfa_recovery.invalid")
      end
    end

    private

    def throttle_recovery_requests!
      throttle_email_flood!(
        flow:          "mfa_recovery",
        email:         params[:email],
        redirect_path: new_mfa_recovery_path(current_customer_id),
        alert:         t("auth.flash.mfa_recovery.throttled")
      )
    end

    # GET is a confirm page so mail scanners / Safe Links prefetch cannot
    # disable MFA. The token is consumed only on the subsequent POST.
    def render_consume_confirm
      @token = params[:token].to_s
      if @token.blank?
        redirect_to new_user_session_path, alert: t("authentication.mfa_recovery.invalid")
        return
      end

      render :consume
    end
  end
end
