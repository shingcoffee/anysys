# frozen_string_literal: true

module SpeechToText
  # Terminal clip state is durable before this best-effort notification. Polls
  # can return the same field transcript if rendering or delivery is down.
  class BroadcastResult
    def self.call(clip:)
      return unless clip.terminal?

      error = clip.status == "failed" ? I18n.t("speech_to_text.widget.#{clip.error_code.presence || 'generic_error'}") : ""
      html = ApplicationController.render(
        SpeechToText::ResultComponent.new(
          clip_id: clip.id, field_id: clip.field_dom_id, status: clip.status,
          transcript: clip.transcript.to_s, error: error
        ),
        layout: false
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        AiAssistant::Stream.user_name(customer_id: clip.customer_id, user_id: clip.user_id),
        target: "speech_to_text_result_#{clip.id}", html: html
      )
    rescue StandardError => e
      Rails.logger.error("[speech_to_text.transcribe] broadcast failed clip=#{clip.id}: #{e.class}: #{e.message}")
    end
  end
end
