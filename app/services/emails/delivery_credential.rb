# frozen_string_literal: true

module Emails
  # Selection for new mail stays in Email::CredentialResolver. An outstanding
  # message uses its pinned account even after that account is unassigned.
  class DeliveryCredential
    def self.metadata(credential)
      { credential_id: credential.id, credential_mode: credential.mode }
    end

    def self.for_message(message, mode: nil)
      identity = message.metadata || {}
      id = identity["credential_id"]
      return Email::CredentialResolver.call(provider: message.provider, mode: mode || Email::CredentialResolver.default_mode) unless id

      credential = Email::CredentialResolver.for_recorded(credential_id: id, provider: message.provider,
                                                           mode: identity["credential_mode"])
      return credential if credential&.configured?

      raise Email::Errors::CredentialsMissing, I18n.t("admin_modules.flash.templates.credentials_missing")
    end
  end
end
