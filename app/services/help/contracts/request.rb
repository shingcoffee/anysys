# frozen_string_literal: true

require "reform/form"

module Help
  module Contracts
    class Request < Reform::Form
      property :subject
      property :body, virtual: true
      property :images, virtual: true

      validates :subject, presence: true, length: { maximum: 120 }
      validates :body, presence: true, length: { maximum: 5000 }
      validate :images_are_allowed

      private

      def images_are_allowed
        Help::AttachmentRules.validate(
          images,
          allowed_types: Help::AttachmentRules::IMAGE_TYPES,
          errors: errors,
          attribute: :images
        )
      end
    end
  end
end
