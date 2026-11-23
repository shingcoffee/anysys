# frozen_string_literal: true

module Admin
  module Modules
    module AiAssistant
      # Conversation history sidebar (JSON). Category (a) admin URL — the
      # admin-or-owner gate and the CanCan route check are applied globally by
      # RouteAuthorization for everything under /:cid/admin/.
      #
      # Tenant and user are never taken from params: every activity resolves
      # its target through AiAssistant::Conversation.resolve, which is scoped
      # to (current_customer, current_user), so another user's or another
      # tenant's thread is indistinguishable from one that does not exist.
      class ConversationsController < ApplicationController
        dashboard_menu_item :assistant

        def index
          result = ::AiAssistant::Activities::ListConversations.call(
            customer: current_customer,
            user: current_user
          )
          return render_failure(result) unless result.success?

          render json: {
            active: result.active.map { |row| serialize(row) },
            archived: result.archived.map { |row| serialize(row) }
          }, status: :ok
        end

        def create
          result = ::AiAssistant::Activities::StartConversation.call(
            customer: current_customer,
            user: current_user
          )
          return render_failure(result) unless result.success?

          render json: { conversation: serialize(result.conversation) }, status: :created
        end

        def update
          result = ::AiAssistant::Activities::RenameConversation.call(
            customer: current_customer,
            user: current_user,
            conversation_id: params[:id],
            title: conversation_params[:title]
          )
          return render_failure(result) unless result.success?

          render json: { conversation: serialize(result.conversation) }, status: :ok
        end

        def archive
          result = ::AiAssistant::Activities::ArchiveConversation.call(
            customer: current_customer,
            user: current_user,
            conversation_id: params[:id],
            archived: conversation_params.fetch(:archived, true)
          )
          return render_failure(result) unless result.success?

          render json: { conversation: serialize(result.conversation) }, status: :ok
        end

        def destroy
          result = ::AiAssistant::Activities::DeleteConversation.call(
            customer: current_customer,
            user: current_user,
            conversation_id: params[:id]
          )
          return render_failure(result) unless result.success?

          render json: { conversation_id: result.conversation.id }, status: :ok
        end

        private

        def conversation_params
          @conversation_params ||= params.permit(:title, :archived)
        end


        # The sidebar highlights the thread the workspace would open, which is
        # the most recently active unarchived one. Read without instantiating a
        # row, and memoised so a list of any length costs one lookup.
        def current_conversation_id
          return @current_conversation_id if defined?(@current_conversation_id)

          @current_conversation_id = ::AiAssistant::Conversation
                                     .owned_by(customer: current_customer, user: current_user)
                                     .active.recent_first.pick(:id)
        end

        def serialize(conversation)
          {
            id: conversation.id,
            title: conversation.display_title,
            archived: conversation.archived?,
            last_active_at: conversation.last_active_at&.iso8601,
            current: conversation.id == current_conversation_id
          }
        end

        def render_failure(result)
          render json: { errors: result.errors }, status: result.http_status
        end
      end
    end
  end
end
