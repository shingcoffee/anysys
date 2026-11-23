# frozen_string_literal: true

module Email
  # Resolves the active email credential for a given mode and (optional) provider.
  # When no provider is named, the default provider is preferred, falling back to
  # any active credential for the mode — so a tenant that has configured exactly
  # one provider "just works".
  class CredentialResolver
    def self.call(mode: default_mode, provider: nil)
      scope = Emails::Credential.active.where(mode: mode)

      credential =
        if provider
          scope.find_by(provider: provider.to_s)
        else
          scope.find_by(provider: Email::Providers.default_key.to_s) || scope.order(:id).first
        end

      return credential if credential

      raise Errors::CredentialsMissing, "no active email credential for mode=#{mode} provider=#{provider || 'any'}"
    end

    def self.default_mode
      Rails.env.production? ? "production" : "sandbox"
    end

    # Receipts belong to the credential that sent the message, even after a
    # delivery-vendor switch. This is deliberately separate from active-only
    # resolution for new sends; callers must supply the recorded identity.
    def self.for_recorded(credential_id:, provider:, mode: nil)
      scope = Emails::Credential.where(id: credential_id, provider: provider.to_s)
      scope = scope.where(mode: mode) if mode.present?
      credential = scope.first if credential_id.present? && provider.present?
      return credential if credential

      raise Errors::CredentialsMissing, "no recorded email credential id=#{credential_id} provider=#{provider}"
    end
  end
end
