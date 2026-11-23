# frozen_string_literal: true

module SpeechToText
  # Shared body for the two dictation-upload endpoints — the cookie-session
  # dashboard endpoint and the desktop Bearer API. They previously carried
  # byte-identical `create` actions that differed only in which surface they
  # represent, so only the surface-specific bits are overridable here.
  #
  # The tenant and user always come from the authenticated request
  # (current_customer / current_user); a client-supplied customer_id is ignored.
  module TranscriptionEnqueueing
    extend ActiveSupport::Concern

    def create
      permitted = transcription_params
      result = ::SpeechToText::Activities::EnqueueTranscription.call(
        customer: current_customer,
        user: current_user,
        audio: permitted[:audio],
        field_dom_id: permitted[:field_dom_id].presence || default_field_dom_id,
        language: permitted[:language].presence,
        duration_seconds: permitted[:duration_seconds],
        destination: dictation_destination,
        conversation_id: permitted[:conversation_id].presence
      )
      render_enqueue_result(result)
    end

    private

    # :customer_id is the URL tenant, not a body field. Permit it so Strong
    # Parameters does not log it five times per upload; tenancy still comes
    # from current_customer, never from this value.
    def transcription_params
      @transcription_params ||= params.permit(
        :audio, :field_dom_id, :language, :duration_seconds, :destination, :conversation_id, :customer_id
      )
    end

    # Surfaces with no DOM to name (the desktop client) override this.
    def default_field_dom_id
      nil
    end

    # The mounted widget declares where its transcript belongs. Unknown values
    # fail closed to "field" in SpeechToText::Clip.normalize_destination, and
    # both destinations only ever touch the requesting user's own records.
    def dictation_destination
      transcription_params[:destination]
    end

    def render_enqueue_result(result)
      if result.success?
        render json: { clip_id: result.clip.id }, status: :accepted
      else
        body = { errors: result.errors }
        body[:clip_id] = result.clip.id if result.clip
        body[:error_code] = result.error_code if result.error_code.present?
        render json: body, status: result.http_status
      end
    end
  end
end
