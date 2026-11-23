# frozen_string_literal: true

require "reform/form"

module SpeechToText
  module Contracts
    # Validates a dictation upload before a Clip is created. Whisper is never
    # called from this contract or its enqueue activity.
    #
    # Every check fails CLOSED: a client that omits the Content-Type or hands
    # over an IO that cannot report its length is rejected, because "we could
    # not tell" must never mean "send it to the paid vendor anyway".
    class Transcription < Reform::Form
      # Lightweight backing object (avoids pulling in OpenStruct).
      Input = Struct.new(:audio, :field_dom_id, :language, :destination)

      MAX_AUDIO_BYTES = 25.megabytes

      property :audio
      property :field_dom_id
      property :language
      property :destination

      validate :audio_present
      validate :audio_size
      validate :audio_content_type
      validate :field_dom_id_present
      validate :destination_known

      def upload
        @upload ||= SpeechToText::AudioUpload.wrap(audio)
      end

      private

      def audio_present
        return if upload.present?

        errors.add(:audio, I18n.t("speech_to_text.errors.audio_blank"))
      end

      def audio_size
        return if upload.blank?

        size = upload.byte_size
        if size.nil?
          errors.add(:audio, I18n.t("speech_to_text.errors.audio_size_unknown"))
        elsif size > MAX_AUDIO_BYTES
          errors.add(:audio, I18n.t("speech_to_text.errors.audio_too_large"))
        end
      end

      # An explicit allowlist of what the dictate widget and the desktop client
      # actually produce, shared with the provider format tables — not a loose
      # "audio/" prefix test that would wave arbitrary bytes through.
      def audio_content_type
        return if upload.blank?
        return if SpeechToText::AudioFormats.permitted_mime?(upload.content_type)

        errors.add(:audio, I18n.t("speech_to_text.errors.audio_content_type"))
      end

      def field_dom_id_present
        return if field_dom_id.to_s.strip.present?

        errors.add(:field_dom_id, I18n.t("speech_to_text.errors.field_dom_id_blank"))
      end

      # Request-shape validation belongs here rather than only on the model.
      # Blank is allowed — the enqueue activity applies the "field" default —
      # but a value the client did supply has to be one we recognise, so a typo
      # surfaces as a 422 instead of being silently coerced.
      def destination_known
        return if destination.blank?
        return if SpeechToText::Clip::DESTINATIONS.include?(destination.to_s)

        errors.add(:destination, I18n.t("speech_to_text.errors.audio_destination"))
      end
    end
  end
end
