# frozen_string_literal: true

require "reform/form"

module Help
  module Contracts
    class Email < Reform::Form
      property :subject, virtual: true
      property :body, virtual: true
      property :attachments, virtual: true
      property :page_url, virtual: true

      validates :subject, presence: true, length: { maximum: 120 }
      validates :body, presence: true, length: { maximum: 5000 }
      validate :attachments_are_allowed

      private

      def attachments_are_allowed
        Help::AttachmentRules.validate(
          attachments,
          allowed_types: Help::AttachmentRules::EMAIL_TYPES,
          errors: errors,
          attribute: :attachments
        )
      end
    end
  end
end
