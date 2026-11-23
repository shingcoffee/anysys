# frozen_string_literal: true

module AiAssistant
  module Providers
    # Abstract base class for an AI Assistant vendor integration. Subclasses must:
    #
    #   - declare a stable `key` (e.g. "openai_whisper") used as the DB row identifier
    #   - declare `default_display_name` — the English fallback shown when no
    #     `ai_assistant.providers.<key>.name` translation exists
    #   - declare `config_fields` — vendor-specific fields the platform-owner UI
    #     should render. These are stored in ProviderSettings#config_json.
    #   - implement `transcribe(io:, filename:, content_type:, language:)` returning
    #       :outcome  — one of :success, :empty, :configuration_error, :unreachable
    #       :text     — String or nil
    #       :raw      — vendor payload (debugging only)
    #   - implement `configured?(settings)` — when may enqueue treat the vendor as ready?
    class Base
      include VendorPlugin.mixin(
        i18n_prefix: "ai_assistant.providers",
        registry:    AiAssistant::Providers,
        inject:      :settings,
        credential_fallback: ->(name) { I18n.t("ai_assistant.platform_settings.#{name}") }
      )

      class << self
        def transcribe(settings:, **kwargs)
          new(settings: settings).transcribe(**kwargs)
        end

        def supports_transcribe? = true
        def supports_generation? = false
        def supports_images?     = true

        # Whether the vendor accepts ruby_llm tool definitions on a chat call.
        # A vendor that does not gets the same turn without the native tool
        # list, so declaring this is the vendor's own business — never a
        # caller-side allowlist.
        def supports_native_tools? = false

        # Whether #chat honours the `on_chunk` callback. A vendor that does not
        # still returns the same result; the panel just falls back to progress
        # steps instead of a live preview.
        def supports_streaming? = false
      end

      def transcribe(io:, filename:, content_type:, language: nil)
        raise NotImplementedError
      end

      # Transcription-only vendors (AWS, Aliyun) leave this default in place.
      # Reply already fail-closes on a non-success outcome.
      def chat(messages:, tools: nil, on_chunk: nil) # rubocop:disable Lint/UnusedMethodArgument
        { outcome: :configuration_error, text: nil, raw: nil }
      end

      # Default health probe: a silent WAV through #transcribe. Generation-only
      # vendors override this (e.g. Cursor lists models).
      def health_check
        probe = StringIO.new(silence_wav)
        probe.set_encoding(Encoding::BINARY)
        transcribe(io: probe, filename: "probe.wav", content_type: "audio/wav")
      end

      private

      def silence_wav
        sample_count = 1600
        data_size = sample_count * 2
        header = [
          "RIFF", 36 + data_size, "WAVE", "fmt ", 16, 1, 1, 8000, 16_000, 2, 16,
          "data", data_size
        ].pack("A4VA4A4VvvVVvva4V")
        header + ("\x00" * data_size)
      end
    end
  end
end
