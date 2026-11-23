# frozen_string_literal: true

module Sms
  # Resolves the active credential to send through, for a given mode and
  # (optional) provider. When no provider is named, the default adapter is
  # preferred, falling back to any active credential for the mode — so a tenant
  # that has configured exactly one vendor "just works".
  class CredentialResolver
    def self.call(mode: default_mode, provider: nil, credential_id: nil)
      scope = Sms::Credential.where(mode: mode)
      if credential_id
        cred = scope.find_by(id: credential_id, provider: provider.to_s)
        return cred if cred&.configured?

        raise Sms::Errors::CredentialsMissing, I18n.t("admin_modules.sms.errors.credentials_missing")
      end
      scope = scope.active

      cred =
        if provider
          scope.find_by(provider: provider.to_s)
        else
          scope.find_by(provider: Sms::Adapters.default_key.to_s) || scope.order(:id).first
        end

      return cred if cred

      raise Sms::Errors::CredentialsMissing, I18n.t("admin_modules.sms.errors.credentials_missing")
    end

    def self.default_mode
      Rails.env.production? ? "production" : "sandbox"
    end
  end
end
