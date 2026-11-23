# frozen_string_literal: true

module Authentication
  class CustomerSignupMailer < ApplicationMailer
    def instructions(email, token)
      @email = email
      @token = token
      mail(
        to: email,
        subject: I18n.t("auth.mailer.customer_signup.subject")
      )
    end
  end
end
