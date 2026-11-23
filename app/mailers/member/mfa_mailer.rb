# frozen_string_literal: true

module Member
  class MfaMailer < ApplicationMailer
    def reset_link
      @user  = params[:user]
      @token = params[:token]
      @url   = consume_mfa_recovery_url(
        customer_id: @user.customer_id,
        token:       @token,
        host:        default_url_options[:host] || "localhost",
        port:        default_url_options[:port]
      )

      mail(
        to:      @user.email,
        subject: t("member.mfa_mailer.subject")
      )
    end
  end
end
