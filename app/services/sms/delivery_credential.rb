# frozen_string_literal: true

module Sms
  class DeliveryCredential
    def self.metadata(credential)
      { credential_id: credential.id, credential_mode: credential.mode }
    end

    # Outstanding messages use the recorded account even after unassignment.
    # Never fall back to today's default account for a missing recorded identity.
    def self.for_message(message, mode: nil)
      identity = message.metadata
      retained(id: identity["credential_id"], provider: message.provider, mode: identity["credential_mode"])
    end

    def self.for_campaign(campaign)
      unless Campaigns::Snapshot.valid?(campaign)
        raise Errors::TemplateVarsInvalid, I18n.t("sms.errors.snapshot_invalid")
      end
      identity = campaign.settings_snapshot
      retained(id: identity.fetch("credential_id"), provider: identity.fetch("provider"), mode: identity.fetch("credential_mode"))
    end

    def self.retained(id:, provider:, mode:)
      credential = Credential.find_by(id: id, provider: provider, mode: mode)
      return credential if credential&.configured?

      raise Errors::CredentialsMissing, I18n.t("admin_modules.sms.errors.credentials_missing")
    end
    private_class_method :retained
  end
end
