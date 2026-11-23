# frozen_string_literal: true

require "json"

module FlowchartRuntime
  # Completions for the ai_inference step. Uses the platform generation
  # provider (AiAssistant::ProviderSettings.active_for(:generation)) and Llm /
  # ruby_llm — never an ad-hoc vendor URL or ENV key the platform does not
  # configure.
  module Ai
    class Error < StandardError; end

    OUTPUT_FORMATS = %w[text json structured].freeze
    LLM_PROVIDERS = {
      "openai_whisper" => :openai,
      "deepseek" => :deepseek,
      "qwen" => :qwen,
      "aws_bedrock" => :bedrock
    }.freeze

    module_function

    def complete(ctx, prompt_template:, model: nil, system_prompt: nil,
                 max_tokens: 1024, temperature: 0.7, output_format: "text",
                 json_repair: false, on_invalid_json: "fail")
      settings = AiAssistant::ProviderSettings.active_for(:generation)
      return Step.fail(ctx, :"ai_inference.not_configured") unless settings

      llm_provider = LLM_PROVIDERS[settings.provider.to_s]
      return Step.fail(ctx, :"ai_inference.unsupported_provider") unless llm_provider

      prompt = Template.interpolate(ctx, prompt_template)
      system = system_prompt.to_s.strip.present? ? Template.interpolate(ctx, system_prompt) : nil
      format_name = OUTPUT_FORMATS.include?(output_format.to_s) ? output_format.to_s : "text"
      json_mode = %w[json structured].include?(format_name)

      messages = []
      messages << { role: "system", content: system } if system.present?
      messages << { role: "user", content: prompt }

      result = Llm.complete(
        **llm_kwargs(settings, llm_provider).merge(
          model: model_name(settings, model),
          messages: messages,
          json: json_mode,
          temperature: temperature,
          max_tokens: max_tokens
        )
      )
      apply_result(ctx, result, format_name, json_repair: json_repair, on_invalid_json: on_invalid_json)
    rescue Template::Error => error
      raise Error, error.message
    end

    def llm_kwargs(settings, llm_provider)
      kwargs = { provider: llm_provider, api_key: settings.api_key }
      organization = settings.config_value(:organization).presence
      kwargs[:organization] = organization if organization
      if llm_provider == :bedrock
        kwargs[:access_key_id] = settings.config_value(:access_key_id)
        kwargs[:region] = settings.config_value(:region)
      end
      kwargs
    end

    def model_name(settings, override)
      override.to_s.strip.presence ||
        settings.config_value(:chat_model).presence ||
        chat_model_default(settings)
    end

    def chat_model_default(settings)
      field = Array(settings.provider_class.config_fields).find { |item| item[:name].to_s == "chat_model" }
      field&.fetch(:default, nil).presence || "default"
    end

    def apply_result(ctx, result, output_format, json_repair:, on_invalid_json:)
      outcome = result.is_a?(Hash) ? result[:outcome] : nil
      case outcome
      when :success
        text = result[:text]
        return Step.fail(ctx, :"ai_inference.empty") if text.to_s.strip.empty?

        format_output(text, output_format, json_repair: json_repair, on_invalid_json: on_invalid_json)
      when :empty
        Step.fail(ctx, :"ai_inference.empty")
      when :configuration_error
        Step.fail(ctx, :"ai_inference.not_configured")
      else
        raise Error, (result.is_a?(Hash) && result.dig(:raw, "error")).to_s.presence || "unreachable"
      end
    end

    def format_output(text, output_format, json_repair: false, on_invalid_json: "fail")
      case output_format
      when "json", "structured"
        parse_json_output(text, json_repair: json_repair, on_invalid_json: on_invalid_json)
      else
        text.to_s
      end
    end

    def parse_json_output(text, json_repair:, on_invalid_json:)
      payload = json_repair ? repair_json(text) : text.to_s
      JSON.parse(payload)
    rescue JSON::ParserError => error
      return text.to_s if on_invalid_json.to_s == "as_text"

      raise Error, error.message
    end

    def repair_json(text)
      stripped = text.to_s.strip
      stripped = stripped.sub(/\A```(?:json)?[[:space:]]*/i, "")
      stripped = stripped.sub(/[[:space:]]*```\z/, "")
      stripped.strip
    end
    private_class_method :llm_kwargs, :model_name, :chat_model_default, :apply_result,
                         :format_output, :parse_json_output, :repair_json
  end
end
