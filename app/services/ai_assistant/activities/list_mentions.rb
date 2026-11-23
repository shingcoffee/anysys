# frozen_string_literal: true

module AiAssistant
  module Activities
    # Read-path for the composer's `@` menu: what this tenant owns that can be
    # mentioned. Never calls a vendor.
    #
    # The composer asks for this when the menu opens rather than reading a list
    # embedded in the page, because the assistant creates entities mid-thread
    # and a page-load snapshot would not contain them.
    class ListMentions
      MODULE_KEY = "ai_assistant"

      Result = Struct.new(:success?, :mentions, :http_status, :errors, keyword_init: true)

      def self.call(customer:, viewer: nil)
        new(customer: customer, viewer: viewer).call
      end

      def initialize(customer:, viewer: nil)
        @customer = customer
        @viewer = viewer
      end

      def call
        return failure unless module_enabled?

        Result.new(
          success?: true,
          mentions: AiAssistant::Assistant::Mentions.candidates(
            customer_id: @customer.id,
            viewer: @viewer
          ),
          http_status: 200,
          errors: []
        )
      end

      private

      def module_enabled?
        FeatureModules::Module.enabled?(key: MODULE_KEY, customer_id: @customer.id)
      end

      def failure
        Result.new(
          success?: false,
          mentions: [],
          http_status: 403,
          errors: [ I18n.t("ai_assistant.errors.module_disabled") ]
        )
      end
    end
  end
end
