# frozen_string_literal: true

module AiAssistant
  # Shared body for the two assistant send endpoints — the cookie-session
  # composer under /:cid/admin/modules/ai_assistant and the desktop Bearer API
  # under /:cid/admin/assistant. They previously carried near-identical
  # `create` actions, so only the surface-specific bits are overridable here.
  #
  # The tenant and the user always come from the authenticated request
  # (current_customer / current_user). `conversation_id` is a client-supplied
  # id and is NOT trusted: AiAssistant::Activities::SendMessage resolves it
  # through AiAssistant::Conversation.resolve, which is scoped to that
  # (customer, user) pair, so naming another user's thread is a 404.
  module MessageSending
    extend ActiveSupport::Concern

    def create
      result = ::AiAssistant::Activities::SendMessage.call(
        customer: current_customer,
        user: current_user,
        body: message_params[:body],
        images: Array(message_params[:images]),
        conversation_id: message_params[:conversation_id],
        proposal_message_id: message_params[:proposal_message_id]
      )

      if result.success?
        render json: { message_id: result.message.id }, status: :accepted
      else
        render json: { errors: result.errors }, status: result.http_status
      end
    end

    private

    # Surfaces that cannot upload (the desktop client posts typed text only)
    # narrow this.
    def message_params
      @message_params ||= params.permit(:body, :conversation_id, :proposal_message_id, images: [])
    end
  end
end
