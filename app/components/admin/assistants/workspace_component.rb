# frozen_string_literal: true

module Admin
  module Assistants
    # Dedicated AI Assistant canvas: chat + artifact, or the offline empty state.
    class WorkspaceComponent < ApplicationComponent
      attr_reader :customer, :user, :assistant_messages, :assistant_conversation

      def initialize(customer:, user:, assistant_available: false, assistant_messages: [], assistant_conversation: nil)
        @customer = customer
        @user = user
        @assistant_available = assistant_available
        @assistant_messages = Array(assistant_messages)
        @assistant_conversation = assistant_conversation
      end

      def assistant_available?
        @assistant_available
      end

      def modules_href
        helpers.admin_maintenance_modules_path(customer.id)
      end

      # Marks the mobile Preview tab when there is something to look at, so the
      # panel behind the tab is discoverable without tapping it first.
      def artifact?
        return @artifact unless @artifact.nil?
        return @artifact = false unless assistant_conversation

        @artifact = AiAssistant::Assistant::Artifact.resolve(assistant_conversation, customer: customer).present?
      end

      def before_render
        helpers.content_for(:container_width, "edge")
        helpers.content_for(:title, I18n.t("ai_assistant.assistant.title"))
      end
    end
  end
end
