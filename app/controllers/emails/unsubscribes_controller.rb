# frozen_string_literal: true

module Emails
  class UnsubscribesController < ApplicationController
    layout "public_page"

    skip_before_action :authenticate_user!, raise: false
    skip_before_action :enforce_mfa!, raise: false

    # RFC 8058 one-click unsubscribes are POSTed by mailbox providers (Gmail,
    # Yahoo) with no session and no CSRF token — the signed token in the path
    # is the sole authorization, so CSRF protection must not apply here.
    skip_forgery_protection

    # Mailbox-provider one-click POSTs (and older webviews opening the GET
    # confirm page) are not Rails `:modern` browsers. Same opt-out as
    # payments checkout / OAuth token endpoints.
    def allow_browser(versions:, block:)
    end

    def show
      @email = Emails::SendActivities::SendActivityUnsubscribe.emailed_address(params[:token])
      render :not_found, status: :not_found and return if @email.blank?
    end

    def create
      user = Emails::SendActivities::SendActivityUnsubscribe.unsubscribe(params[:token])
      if user
        @email = Emails::SendActivities::SendActivityUnsubscribe.emailed_address(params[:token])
        render :confirmed
      else
        render :not_found, status: :not_found
      end
    end
  end
end
