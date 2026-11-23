# frozen_string_literal: true

module Admin
  class AssistantsController < ApplicationController
    dashboard_menu_item :assistant

    def show
      assign_assistant
    end

    private

    def assign_assistant
      return unless assistant_available?

      conversation = requested_conversation
      return redirect_to_canonical if conversation.nil?

      @assistant_available = true
      @assistant_conversation = conversation
      @assistant_messages = conversation.messages.with_attached_images.order(:id).to_a
    end

    # Which thread to open. `?conversation=<id>` is a client-supplied id and is
    # resolved through AiAssistant::Conversation.resolve, which is scoped to
    # (current_customer, current_user) — so another user's or another tenant's
    # thread resolves to nil rather than rendering.
    #
    # A query param rather than a path segment: /:cid/admin/assistant/... is
    # already taken by the desktop Bearer API (namespace :assistant), which
    # rejects cookie sessions.
    def requested_conversation
      AiAssistant::Conversation.resolve(
        customer: current_customer,
        user: current_user,
        id: params[:conversation]
      )
    end

    def redirect_to_canonical
      redirect_to admin_assistant_path(current_customer.id),
                  alert: t("ai_assistant.errors.conversation_not_found")
    end

    def assistant_available?
      FeatureModules::Module.enabled?(key: "ai_assistant", customer_id: current_customer.id) &&
        AiAssistant::ProviderSettings.active_for(:generation).present?
    end
  end
end
