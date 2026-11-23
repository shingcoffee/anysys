# frozen_string_literal: true

require "reform/form"

module AiAssistant
  module Contracts
    class Message < Reform::Form
      # Lightweight backing object (avoids pulling in OpenStruct).
      Input = Struct.new(:body, :images)

      MAX_BODY = 8_000

      property :body
      property :images

      validate :body_present
      validate :body_length
      validate :images_allowed

      private

      def body_present
        return if body.to_s.strip.present?
        return if AiAssistant::Assistant::Attachments.present?(images)

        errors.add(:body, I18n.t("ai_assistant.errors.body_blank"))
      end

      def body_length
        return if body.to_s.length <= MAX_BODY

        errors.add(:body, I18n.t("ai_assistant.errors.body_too_long"))
      end

      def images_allowed
        AiAssistant::Assistant::Attachments.validate(images, errors: errors)
      end
    end
  end
end
