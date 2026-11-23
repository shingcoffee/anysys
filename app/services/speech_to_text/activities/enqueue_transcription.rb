# frozen_string_literal: true

module SpeechToText
  module Activities
    # Request-path enqueue: validate the upload, fail closed if the module or
    # vendor is off, attach audio to an ephemeral Clip, and hand off to
    # TranscribeJob. NEVER calls Whisper (or any other STT/LLM vendor).
    class EnqueueTranscription
      include AiAssistant::Activities::Preflight

      class Result < AiAssistant::Activities::Preflight::Result
        alias_method :clip, :record
      end

      def self.call(customer:, user:, audio:, field_dom_id:, language: nil,
                    duration_seconds: nil, destination: nil, conversation_id: nil)
        new(customer: customer, user: user, audio: audio,
            field_dom_id: field_dom_id, language: language,
            duration_seconds: duration_seconds, destination: destination, conversation_id: conversation_id).call
      end

      def initialize(customer:, user:, audio:, field_dom_id:, language: nil,
                     duration_seconds: nil, destination: nil, conversation_id: nil)
        @customer = customer
        @user = user
        @audio = audio
        @field_dom_id = field_dom_id
        @language = language
        @duration_seconds = duration_seconds
        @destination = destination
        @conversation_id = conversation_id
      end

      def call
        failure = preflight_failure
        return failure if failure

        clip = create_clip!
        job = SpeechToText::TranscribeJob.perform_later(clip.id)
        unless job && (!job.respond_to?(:successfully_enqueued?) || job.successfully_enqueued?)
          return enqueue_failure(clip)
        end
        success_result(clip)
      rescue StandardError => e
        clip ||= @created_clip
        Rails.logger.error("[speech_to_text.enqueue] clip=#{clip&.id}: #{e.class}: #{e.message}")
        if !clip&.persisted? && e.is_a?(ActiveRecord::RecordNotFound) && resolved_destination == "assistant"
          return fail_result(404, [I18n.t("ai_assistant.errors.conversation_not_found")])
        end
        raise unless clip&.persisted?

        enqueue_failure(clip)
      end

      private

      attr_reader :customer, :user, :audio, :field_dom_id, :language, :duration_seconds, :destination, :conversation_id

      def rate_scope = "enqueue"

      def rate_limited_scope
        "speech_to_text.errors"
      end

      # Length is checked before the module/provider/rate guards so an
      # over-long clip always reports `too_long` to the widget.
      def activity_guard
        if resolved_destination == "assistant"
          return fail_result(404, [I18n.t("ai_assistant.errors.conversation_not_found")]) unless authorized_conversation
        end
        return duration_failure if too_long?

        AudioProbe.call(upload: upload, max_duration: tenant_max_duration)
        nil
      rescue AudioProbe::TooLong
        duration_failure
      rescue AudioProbe::Unavailable
        fail_result(503, [I18n.t("speech_to_text.widget.disabled")], error_code: "audio_probe_unavailable")
      rescue AudioProbe::InvalidAudio
        fail_result(422, [I18n.t("speech_to_text.errors.audio_content_type")], error_code: "invalid_audio")
      end

      def duration_failure
        fail_result(422, [ I18n.t("speech_to_text.errors.too_long") ], error_code: "too_long")
      end

      def contract_valid?
        contract.validate(
          audio: audio, field_dom_id: field_dom_id, language: language, destination: resolved_destination
        )
      end

      def contract
        @contract ||= SpeechToText::Contracts::Transcription.new(
          SpeechToText::Contracts::Transcription::Input.new
        )
      end

      def contract_errors
        contract.errors.full_messages
      end

      def too_long?
        client_duration_too_long? || byte_size_exceeds_duration_cap?
      end

      def client_duration_too_long?
        seconds = Integer(duration_seconds, exception: false)
        return true if seconds.nil? || seconds.negative?

        seconds > tenant_max_duration
      end

      # A cheap request-size guard in addition to decoded duration. A small
      # compressed file can still be too long; AudioProbe makes that decision.
      def byte_size_exceeds_duration_cap?
        size = upload.byte_size
        return false if size.nil?

        size > SpeechToText::AudioFormats.max_bytes_for(
          tenant_max_duration, filename: upload.filename, content_type: upload.content_type
        )
      end

      def upload
        @upload ||= SpeechToText::AudioUpload.wrap(audio)
      end

      def tenant_max_duration
        @tenant_max_duration ||= SpeechToText::DurationPolicy.max_duration_seconds(customer_id: customer.id)
      end

      def assignment
        @assignment ||= SpeechToText::DurationPolicy.assignment(customer.id)
      end

      def create_clip!
        operation = lambda do
          clip = @created_clip = SpeechToText::Clip.create!(
            customer: customer, user: user, field_dom_id: field_dom_id.to_s,
            destination: resolved_destination, conversation: authorized_conversation,
            language: resolved_language, status: "pending"
          )
          upload.attach_to(clip.audio)
          clip
        end
        return operation.call unless authorized_conversation

        authorized_conversation.with_lock(&operation)
      end

      def authorized_conversation
        return nil unless resolved_destination == "assistant"
        return nil if conversation_id.blank?

        @authorized_conversation ||= AiAssistant::Conversation.owned_by(customer: customer, user: user)
                                                             .find_by(id: conversation_id)
      end

      def enqueue_failure(clip)
        Clip.where(id: clip.id, status: "pending").update_all(
          status: "failed", error_code: "generic_error", updated_at: Time.current
        )
        clip.reload
        begin
          clip.audio.purge if clip.terminal? && clip.audio.attached?
        rescue StandardError => e
          Rails.logger.error("[speech_to_text.enqueue] purge failed clip=#{clip.id}: #{e.class}: #{e.message}")
        end
        self.class::Result.new(success?: false, record: clip, http_status: 503,
                              errors: [I18n.t("speech_to_text.widget.generic_error")], error_code: "enqueue_failed")
      end

      # Recorded at enqueue time so the job never has to guess from a DOM id
      # whether the transcript belongs in a field or in the assistant thread.
      # Unknown values fail closed to the harmless option (fill the caller's own
      # field) rather than posting into their assistant conversation.
      def resolved_destination
        SpeechToText::Clip.normalize_destination(destination)
      end

      def resolved_language
        return language.to_s if language.to_s.strip.present?

        assignment&.configuration_json&.dig("language").presence || "auto"
      end
    end
  end
end
