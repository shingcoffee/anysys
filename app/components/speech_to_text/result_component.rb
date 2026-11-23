# frozen_string_literal: true

module SpeechToText
  # Hidden Turbo-replace target. The transcribe job broadcasts this node;
  # speech-to-text-result writes the transcript into the host field on connect.
  class ResultComponent < ApplicationComponent
    attr_reader :clip_id, :field_id, :status, :transcript, :error

    def initialize(clip_id:, field_id:, status:, transcript: nil, error: nil, **html_attributes)
      @clip_id = clip_id
      @field_id = field_id
      @status = status
      @transcript = transcript
      @error = error
      @html_attributes = html_attributes
    end

    def dom_id
      "speech_to_text_result_#{clip_id}"
    end

    def wrapper_attributes
      merge_html_attributes(
        {
          id: dom_id,
          class: "hidden",
          data: {
            controller: "speech-to-text-result",
            speech_to_text_result_field_id_value: field_id,
            speech_to_text_result_status_value: status,
            speech_to_text_result_transcript_value: transcript.to_s,
            speech_to_text_result_error_value: error.to_s
          }
        },
        @html_attributes
      )
    end
  end
end
