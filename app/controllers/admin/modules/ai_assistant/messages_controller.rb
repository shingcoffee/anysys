# frozen_string_literal: true

module Admin
  module Modules
    module AiAssistant
      class MessagesController < ApplicationController
        include ::AiAssistant::MessageSending

        dashboard_menu_item :assistant

        # Feeds the composer's `@` menu with what this tenant owns.
        def mentions
          result = ::AiAssistant::Activities::ListMentions.call(
            customer: current_customer,
            viewer: current_user
          )

          if result.success?
            render json: { mentions: result.mentions.map(&:as_json) }, status: :ok
          else
            render json: { errors: result.errors }, status: result.http_status
          end
        end

        def stop
          result = ::AiAssistant::Activities::CancelReply.call(
            customer: current_customer,
            user: current_user,
            conversation_id: message_params[:conversation_id]
          )
          render json: {}, status: result.http_status
        end

        def regenerate
          result = ::AiAssistant::Activities::RegenerateLast.call(
            customer: current_customer,
            user: current_user,
            conversation_id: message_params[:conversation_id]
          )
          if result.success?
            render json: { message_id: result.message.id }, status: :accepted
          else
            render json: { errors: result.errors }, status: result.http_status
          end
        end

        # A Turbo form post from the reply's Undo button; the reply is redrawn
        # in place, carrying the refusal when the undo could not run.
        def undo
          result = ::AiAssistant::Activities::UndoWebsiteReply.call(
            customer: current_customer,
            user: current_user,
            message_id: params[:id]
          )
          return head(result.http_status) unless result.message

          component = ::AiAssistant::MessageComponent.new(message: result.message, undo_errors: result.errors)
          render turbo_stream: turbo_stream.replace(helpers.dom_id(result.message), component), status: result.http_status
        end

        # Discard retires a parked proposal in place; no turn is spent.
        def discard_proposal
          result = ::AiAssistant::Activities::DiscardProposal.call(
            customer: current_customer,
            user: current_user,
            message_id: params[:id]
          )
          return head(result.http_status) unless result.message

          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(result.message),
            ::AiAssistant::MessageComponent.new(message: result.message)
          ), status: result.http_status
        end

        # Cancel stops the conversation's sub-system build; the reply is
        # redrawn with the build's new state.
        def cancel_build
          result = ::AiAssistant::Activities::CancelSubsystemBuild.call(
            customer: current_customer,
            user: current_user,
            message_id: params[:id]
          )
          return head(result.http_status) unless result.message

          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(result.message),
            ::AiAssistant::MessageComponent.new(message: result.message)
          ), status: result.http_status
        end
      end
    end
  end
end
