# frozen_string_literal: true

module SpeechToText
  module Activities
    # Job-only transcription. Resolves the active vendor, opens the attached
    # audio, calls the provider wrap, persists a terminal result, broadcasts a
    # Turbo Stream replace, then purges the blob. The clip row is kept so the
    # desktop client can poll. Never invoked from a Puma request thread.
    #
    # A successful transcript is routed by the clip's recorded destination: an
    # assistant clip becomes a user turn in the chat thread, a field clip is
    # broadcast back for SpeechToText::ResultComponent to write into the input
    # it was dictated from.
    #
    # One worker atomically claims each pending clip. Routing and publication
    # failures cannot regress terminal state; a persistence outage keeps audio
    # for scheduled recovery instead of leaving a purged pending clip.
    class Transcribe
      LOG_TAG = "[speech_to_text.transcribe]"

      SEND_ERROR_CODES = {
        429 => "rate_limited",
        403 => "disabled"
      }.freeze

      Outcome = Struct.new(:status, :transcript, :error, :error_code, keyword_init: true)

      def self.call(clip:)
        new(clip: clip).call
      end

      def initialize(clip:)
        @clip = clip
      end

      def call
        return unless claim!

        outcome = transcribe_clip
        outcome = route_transcript(outcome) if outcome.status == "succeeded"
        finalize(outcome)
      rescue StandardError => e
        report(e, "transcription pipeline failed")
        finalize(failed("generic_error")) if @claimed
      ensure
        # Keep audio on a persistence outage: recovery must terminalize the
        # durable row before deletion. A duplicate worker never purges it.
        purge_audio if @terminalized
      end

      private

      attr_reader :clip

      def claim!
        now = Time.current
        @claimed = Clip.where(id: clip.id, status: "pending").update_all(
          status: "processing", started_at: now, updated_at: now
        ) == 1
        clip.reload if @claimed
        @claimed
      end

      def transcribe_clip
        unless FeatureModules::Module.enabled?(key: "ai_assistant", customer_id: clip.customer_id)
          return failed("disabled")
        end

        settings = AiAssistant::ProviderSettings.active_for(:transcribe)
        return failed("disabled") unless settings
        return failed("generic_error") unless clip.audio.attached?

        result = clip.audio.open do |file|
          settings.provider_class.new(settings: settings).transcribe(
            io: file,
            filename: clip.audio.filename.to_s,
            content_type: clip.audio.content_type,
            language: clip.language
          )
        end
        map_outcome(result)
      rescue StandardError => e
        report(e, "vendor call failed")
        failed("generic_error")
      end

      # An assistant clip's transcript is consumed by the chat thread, so the
      # broadcast payload is cleared — the composer must not also receive it.
      # A field clip keeps its transcript so the result node can fill the input.
      #
      # The thread is pinned and authorized at enqueue. Never resolve a blank
      # id here: a deleted thread must not redirect audio into a newer thread.
      def route_transcript(outcome)
        return outcome unless clip.assistant?
        return failed("generic_error") if clip.conversation_id.blank?

        chat = AiAssistant::Activities::SendMessage.call(
          customer: clip.customer,
          user: clip.user,
          body: outcome.transcript,
          conversation_id: clip.conversation_id,
          idempotency_key: "speech_to_text:clip:#{clip.id}"
        )
        return Outcome.new(status: "succeeded", transcript: "", error: "", error_code: nil) if chat.success?

        code = SEND_ERROR_CODES.fetch(chat.http_status.to_i, "generic_error")
        failed(code)
      end

      def map_outcome(result)
        case result[:outcome]
        when :success
          Outcome.new(status: "succeeded", transcript: result[:text].to_s, error: "", error_code: nil)
        when :empty then failed("empty")
        when :unreachable then failed("vendor_down")
        when :configuration_error then failed("disabled")
        else failed("generic_error")
        end
      end

      def failed(widget_key)
        Outcome.new(
          status: "failed", transcript: "",
          error: I18n.t("speech_to_text.widget.#{widget_key}"), error_code: widget_key
        )
      end

      # Guarantees a terminal status and a broadcast. If persisting the real
      # outcome fails, downgrade to a generic failure so the widget stops
      # spinning instead of waiting on a clip that will never resolve.
      def finalize(outcome)
        return unless persist_outcome(outcome)

        @terminalized = true
        SpeechToText::BroadcastResult.call(clip: clip.reload)
      end

      def persist_outcome(outcome)
        return true if clip.nil? || clip.destroyed?

        Clip.where(id: clip.id, status: "processing").update_all(
          status: outcome.status, error_code: outcome.error_code,
          transcript: outcome.transcript, updated_at: Time.current
        ) == 1
      rescue StandardError => e
        report(e, "persisting outcome failed")
        false
      end

      def purge_audio
        return if clip.nil? || clip.destroyed?

        clip.audio.purge if clip.audio.attached?
      rescue StandardError => e
        report(e, "purging audio failed")
      end

      # These rescues exist so one clip cannot wedge the queue, but a silent
      # rescue makes vendor/integration breakage invisible in production.
      def report(error, context)
        Rails.logger.error(
          "#{LOG_TAG} #{context} clip=#{clip&.id}: #{error.class}: #{error.message}"
        )
      end
    end
  end
end
