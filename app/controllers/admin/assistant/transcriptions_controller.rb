# frozen_string_literal: true

module Admin
  module Assistant
    # Desktop PKCE Bearer API for assistant microphone STT. Cookie sessions
    # are rejected — see Oauth::BearerAuthenticatable.
    class TranscriptionsController < ApplicationController
      include Oauth::BearerAuthenticatable
      include ::SpeechToText::TranscriptionEnqueueing

      DESKTOP_FIELD_DOM_ID = "desktop"

      def show
        result = ::SpeechToText::Activities::ShowTranscription.call(
          customer: current_customer,
          user: current_user,
          clip_id: params[:id]
        )

        if result.success?
          render json: serialize_clip(result.clip)
        else
          render json: { error: "not_found" }, status: :not_found
        end
      end

      private

      # The desktop client has no DOM field to fill.
      def default_field_dom_id
        DESKTOP_FIELD_DOM_ID
      end

      # This surface IS the assistant microphone, so the destination is fixed
      # rather than taken from the request.
      def dictation_destination
        ::SpeechToText::Clip::DESTINATION_ASSISTANT
      end

      def serialize_clip(clip)
        body = { id: clip.id, status: clip.status }
        body[:conversation_id] = clip.conversation_id if clip.conversation_id.present?
        # Assistant dictation is consumed by its pinned thread, not the client.
        # Only an owned, successfully completed field clip returns raw text.
        body[:transcript] = clip.transcript.to_s if clip.field? && clip.status == "succeeded"
        return body if clip.error_code.blank?

        body[:error_code] = clip.error_code
        body[:errors] = [ widget_error(clip.error_code) ]
        body
      end

      def widget_error(code)
        I18n.t("speech_to_text.widget.#{code}", default: I18n.t("speech_to_text.widget.generic_error"))
      end
    end
  end
end
