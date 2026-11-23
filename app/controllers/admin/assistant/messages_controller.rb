# frozen_string_literal: true

module Admin
  module Assistant
    # Desktop PKCE Bearer API for the admin AI assistant (typed wording).
    # Cookie sessions are rejected — see Oauth::BearerAuthenticatable.
    class MessagesController < ApplicationController
      include Oauth::BearerAuthenticatable
      include ::AiAssistant::MessageSending

      def index
        result = ::AiAssistant::Activities::ListMessages.call(
          customer: current_customer,
          user: current_user,
          conversation_id: params[:conversation_id]
        )

        if result.success?
          render json: {
            messages: result.messages.map { |message| serialize_message(message) },
            pending_reply: result.pending_reply
          }
        else
          render json: { errors: result.errors }, status: result.http_status
        end
      end

      private

      # The desktop client posts typed text, never an upload.
      def message_params
        @message_params ||= params.permit(:body, :conversation_id)
      end

      def serialize_message(message)
        {
          id: message.id,
          role: message.role,
          body: message.body,
          status: message.status,
          created_at: message.created_at.iso8601
        }
      end
    end
  end
end
