# frozen_string_literal: true

module AiAssistant
  module Activities
    # Read-path for the workspace sidebar: this user's threads in this tenant,
    # split into the open list and the archived one. Never calls a vendor.
    class ListConversations
      include AiAssistant::Activities::ConversationScoped

      Lists = Struct.new(:active, :archived, keyword_init: true)

      class Result < Preflight::Result
        alias_method :lists, :record

        def active
          lists&.active || []
        end

        def archived
          lists&.archived || []
        end
      end

      def self.call(customer:, user:)
        new(customer: customer, user: user).call
      end

      def initialize(customer:, user:)
        @customer = customer
        @user = user
      end

      def call
        failure = preflight_failure
        return failure if failure

        success_result(
          Lists.new(
            active: titled(rows.active),
            archived: titled(rows.archived.limit(AiAssistant::Conversation::ARCHIVED_LIMIT))
          ),
          http_status: 200
        )
      end

      private

      attr_reader :customer, :user

      # An untitled thread borrows its opening prompt, which is a query per row
      # unless it is resolved for the whole list up front.
      def titled(scope)
        AiAssistant::Conversation.preload_fallback_titles(scope.to_a)
      end

      # One scope, two orderings of the same index
      # (customer_id, user_id, archived_at, last_active_at).
      def rows
        AiAssistant::Conversation
          .owned_by(customer: customer, user: user)
          .recent_first
      end
    end
  end
end
