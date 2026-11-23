# frozen_string_literal: true

require "reform/form"

module Member
  module Profiles
    # Reform contract for member self-service profile updates. Mirrors
    # Authentication::User's validations so behavior is consistent whether
    # the user updates via Devise or this contract.
    class UpdateContract < Reform::Form
      property :first_name
      property :last_name
      property :email
      property :current_password, virtual: true

      validates :first_name, presence: true, length: { maximum: 50 }
      validates :last_name,  presence: true, length: { maximum: 50 }
      validates :email,      presence: true,
                             format: { with: URI::MailTo::EMAIL_REGEXP }

      validate :email_unique
      validate :email_change_authenticated

      private

      def email_unique
        return if email.blank?

        scope = ::Authentication::User
                  .where("LOWER(email) = ?", email.to_s.downcase.strip)
        scope = scope.where.not(id: model.id) if model.persisted?
        errors.add(:email, I18n.t("member.profiles.errors.email_taken")) if scope.exists?
      end

      # reconfirmable is off, so an email swap takes effect immediately and
      # redirects password-reset / sign-in-link mail. Mirror the Devise
      # account-edit guard: passwordless accounts cannot change email;
      # passworded accounts must prove current_password.
      def email_change_authenticated
        return unless email_changing?

        unless model.password_set?
          errors.add(:email, I18n.t("member.profiles.errors.email_requires_password"))
          return
        end

        authenticated = Authentication::PasswordVerification.authenticate(
          user: model, password: current_password.to_s
        )
        return if authenticated

        errors.add(:current_password, I18n.t("member.profiles.errors.current_password_invalid"))
      end

      def email_changing?
        email.to_s.downcase.strip != model.email.to_s.downcase.strip
      end
    end
  end
end
