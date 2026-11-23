# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Prompt chips for the one-thread dashboard welcome. Never lists threads.
    class WelcomePrompts
      LIMIT = 2
      Chip = Struct.new(:kind, :label, :prompt, keyword_init: true)

      def self.call(customer_id:, messages: [])
        new(customer_id: customer_id, messages: messages)
      end

      def initialize(customer_id:, messages: [])
        @customer_id = customer_id
        @messages = Array(messages)
      end

      def continue_prompt
        last = @messages.reverse.find { |msg| msg.respond_to?(:user?) ? msg.user? : msg.role.to_s == "user" }
        last&.body.to_s.strip.presence
      end

      def chips
        entity_chips + page_chips
      end

      private

      def entity_chips
        Entity.for_customer(@customer_id).visible.non_bridge.order(updated_at: :desc).limit(LIMIT).map do |entity|
          Chip.new(
            kind: "entity",
            label: entity.name,
            prompt: I18n.t("ai_assistant.assistant.prompts.recent_entity", name: entity.name)
          )
        end
      end

      def page_chips
        Page.for_customer(@customer_id).visible.order(updated_at: :desc).limit(LIMIT).map do |page|
          Chip.new(
            kind: "page",
            label: page.name,
            prompt: I18n.t("ai_assistant.assistant.prompts.recent_page", name: page.name)
          )
        end
      end
    end
  end
end
