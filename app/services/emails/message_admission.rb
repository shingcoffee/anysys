# frozen_string_literal: true

module Emails
  # Capability inspection has no external side effects and reserves no quota.
  # The provider sees the same envelope shape it will receive from the ledger.
  class MessageAdmission
    def self.validate!(credential:, attributes:)
      provider = Email::Providers.for(credential.provider).new(credential: credential)
      provider.validate_message!(message: Message.new(attributes))
    end

    def self.validate_campaign!(template:, credential: nil)
      credential ||= Email::CredentialResolver.call
      validate!(credential: credential, attributes: {
        customer_id: template.customer_id,
        message_type: "campaign",
        body_html: CompileTemplate.call(template),
        metadata: { attachment_blob_ids: CompileTemplate.blob_ids_for(template) }
      })
    end
  end
end
