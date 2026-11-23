# frozen_string_literal: true

module Authentication
  class SignInLinkMailer < ApplicationMailer
    def sign_in_link(user, token)
      @resource = user
      @token = token
      mail(
        to: user.email,
        subject: I18n.t("auth.mailer.sign_in_link.subject")
      )
    end
  end
end
