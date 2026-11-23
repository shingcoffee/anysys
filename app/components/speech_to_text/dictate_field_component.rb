# frozen_string_literal: true

module SpeechToText
  # Wraps a text/textarea input with a trailing dictate control. Used by the
  # dashboard assistant composer. When the widget is hidden the original input
  # is still emitted so the field is never dropped (ViewComponent's render?
  # hook would otherwise swallow the block).
  class DictateFieldComponent < ApplicationComponent
    attr_reader :field_id, :html_attributes, :destination, :conversation_id

    WIDGET_COPY = {
      mic_label: "Dictate",
      stop_label: "Stop recording",
      recording: "Recording…",
      transcribing: "Transcribing…",
      permission_denied: "Microphone permission denied.",
      no_microphone: "No microphone was found.",
      insecure: "Voice input requires HTTPS or localhost.",
      unavailable: "Voice input is not available in this browser.",
      too_long: "Recording is too long (maximum {seconds} seconds).",
      too_large: "Audio file is too large.",
      generic_error: "Could not transcribe audio. Try again.",
      rate_limited: "Too many transcriptions. Try again later."
    }.freeze

    renders_one :trailing_actions

    # @param destination [Symbol, String] where a finished transcript goes —
    #   :field fills the wrapped input (the default for a reusable dictate
    #   control), :assistant posts it to the AI assistant as a user turn (the
    #   dashboard composer). Sent to the server and recorded on the Clip, so the
    #   transcribe job never has to guess from the field's DOM id.
    def initialize(field_id:, layout: :inline, destination: SpeechToText::Clip::DESTINATION_FIELD,
                   conversation_id: nil, **html_attributes)
      @field_id = field_id
      @layout = layout.to_sym
      @destination = SpeechToText::Clip.normalize_destination(destination)
      @conversation_id = conversation_id
      @html_attributes = html_attributes
    end

    def composer_layout?
      @layout == :composer
    end

    # Visibility predicate for specs and the template. ViewComponent also uses
    # this hook; #render_in forces the template to run so a hidden widget still
    # emits the original input (otherwise the wrap would drop the field).
    def render?
      return true if @force_template

      show_widget?
    end

    def show_widget?
      return @show_widget if defined?(@show_widget)

      @show_widget = widget_eligible?
    rescue NameError
      @show_widget = false
    end

    def render_in(view_context, &block)
      @force_template = true
      super
    ensure
      @force_template = false
    end

    def transcribe_url
      cid = customer_id
      return "" if cid.blank?

      "/#{cid}/admin/modules/ai_assistant/transcriptions"
    end

    # Resolved through DurationPolicy so the browser is told exactly the cap the
    # server enforces. Reading and clamping it here independently let the widget
    # advertise a limit that EnqueueTranscription would then reject.
    def max_duration_seconds
      SpeechToText::DurationPolicy.max_duration_seconds(customer_id: customer_id)
    rescue StandardError
      SpeechToText::DurationPolicy::DEFAULT_MAX_DURATION
    end

    def csrf_token
      form_authenticity_token.to_s
    rescue StandardError
      ""
    end

    def customer_id
      safe_customer_id
    end

    def current_user_id
      safe_current_user&.id
    end

    def stream_signed_in?
      current_user_id.present? && customer_id.present?
    end

    def copy(key)
      english = WIDGET_COPY.fetch(key)
      I18n.t("speech_to_text.widget.#{key}", default: english)
    end

    def wrapper_attributes
      merge_html_attributes(
        {
          class: "w-full",
          data: stimulus_data
        },
        html_attributes
      )
    end

    def stream_name
      [:ai_assistant, customer_id, current_user_id]
    end

    private

    def widget_eligible?
      return false unless safe_current_user&.admin_or_owner?

      cid = safe_customer_id
      return false unless FeatureModules::Module.enabled?(key: "ai_assistant", customer_id: cid)

      provider_configured?
    end

    def safe_current_user
      helpers.current_user
    rescue StandardError
      nil
    end

    def safe_customer_id
      helpers.current_customer&.id || Current.customer_id
    rescue StandardError
      Current.customer_id
    end

    def provider_configured?
      AiAssistant::ProviderSettings.respond_to?(:active_for) &&
        AiAssistant::ProviderSettings.active_for(:transcribe).present?
    rescue NameError
      false
    end

    def stimulus_data
      {
        controller: "speech-to-text",
        action: "ai-assistant:conversationChanged@window->speech-to-text#conversationChanged",
        speech_to_text_url_value: transcribe_url,
        speech_to_text_destination_value: destination,
        speech_to_text_conversation_id_value: conversation_id.to_s,
        speech_to_text_max_duration_value: max_duration_seconds,
        speech_to_text_csrf_value: csrf_token,
        speech_to_text_mic_label_value: copy(:mic_label),
        speech_to_text_stop_label_value: copy(:stop_label),
        speech_to_text_recording_value: copy(:recording),
        speech_to_text_transcribing_value: copy(:transcribing),
        speech_to_text_permission_denied_value: copy(:permission_denied),
        speech_to_text_no_microphone_value: copy(:no_microphone),
        speech_to_text_insecure_value: copy(:insecure),
        speech_to_text_unavailable_value: copy(:unavailable),
        speech_to_text_too_long_value: copy(:too_long),
        speech_to_text_too_large_value: copy(:too_large),
        speech_to_text_generic_error_value: copy(:generic_error),
        speech_to_text_rate_limited_value: copy(:rate_limited)
      }
    end
  end
end
