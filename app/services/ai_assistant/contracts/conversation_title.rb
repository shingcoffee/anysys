# frozen_string_literal: true

require "reform/form"

module AiAssistant
  module Contracts
    # Validation for a sidebar rename. The model caps the column length too;
    # this is what turns an over-long title into a message the user can read
    # instead of a RecordInvalid.
    class ConversationTitle < Reform::Form
      # Lightweight backing object (avoids pulling in OpenStruct).
      Input = Struct.new(:title)

      property :title

      validate :title_present
      validate :title_length

      # What the caller should persist: the collapsed form, so a title padded
      # with whitespace or newlines cannot exceed the column limit.
      def normalized_title
        AiAssistant::Conversation.collapse_whitespace(title)
      end

      private

      def title_present
        return if normalized_title.present?

        errors.add(:title, I18n.t("ai_assistant.errors.title_blank"))
      end

      def title_length
        return if normalized_title.length <= AiAssistant::Conversation::TITLE_LIMIT

        errors.add(:title, I18n.t("ai_assistant.errors.title_too_long"))
      end
    end
  end
end
