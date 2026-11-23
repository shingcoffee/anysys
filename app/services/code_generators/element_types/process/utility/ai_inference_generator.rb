# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class AiInferenceGenerator < BaseGenerator
          OUTPUT_FORMATS = FlowchartRuntime::Ai::OUTPUT_FORMATS
          ON_INVALID_JSON = %w[fail as_text].freeze

          generator_metadata do
            description "Runs one chat completion through the platform generation provider " \
                        "(AiAssistant::ProviderSettings.active_for(:generation) via Llm) and stores " \
                        "the answer on resultVar (default ai_response). Use this to summarise or " \
                        "extract fields from a submit, not for the admin assistant. promptTemplate " \
                        "and systemPrompt are Liquid over ctx ({{ text }}). Blank model uses the " \
                        "provider chat_model. text stores a string; json and structured parse JSON " \
                        "(jsonRepair strips fences; onInvalidJson as_text keeps the raw string). " \
                        "Fails as not_configured when no provider is active, unsupported_provider " \
                        "for Cursor, empty when the model returns blank, and failed on transport errors."
            category :utility
            version "3.0.0"
            presentation icon: "M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z",
                         color: "purple", single_use: false, privileged: false
          end

          config_schema do
            literal :promptTemplate, required: true, example: "Summarize: {{ text }}", multiline: true, placeholder: true,
                    description: "Liquid user prompt interpolated from ctx, such as Summarize: {{ text }}. " \
                                 "Required. Keep it short; the platform model fills the completion."
            literal :systemPrompt, multiline: true, placeholder: true,
                    description: "Optional Liquid system instructions interpolated from ctx, such as " \
                                 "You are a clerk for {{ org_name }}. Leave blank for none."
            literal :model, placeholder: true,
                    description: "Optional chat-model id that overrides the provider chat_model, such as " \
                                 "deepseek-chat or qwen-plus. Leave blank to use the platform setting."
            integer :maxTokens, min: 1, max: 128_000, default: 1024,
                    description: "Maximum tokens requested from the provider (1-128000). Default 1024."
            decimal :temperature, min: 0, max: 2, default: 0.7,
                    description: "Sampling temperature from 0 (deterministic) to 2. Default 0.7."
            enum :outputFormat, OUTPUT_FORMATS, default: "text",
                 description: "How the answer is stored. text keeps the string. json parses JSON into a " \
                              "Hash (onInvalidJson can keep the string). structured also parses JSON " \
                              "and always fails when it is invalid. json and structured ask the model for JSON."
            flag :jsonRepair, default: false, visible: { outputFormat: %w[json structured] }, group: :advanced,
                 description: "When true, strip markdown fences (```json ... ```) before JSON.parse. " \
                              "Default false. Shown for json and structured."
            enum :onInvalidJson, ON_INVALID_JSON, default: "fail", visible: { outputFormat: "json" }, group: :advanced,
                 description: "When JSON.parse fails for outputFormat json: fail refuses the step; " \
                              "as_text stores the raw model text and continues. Default fail. Hidden for structured."
            output :resultVar, default: "ai_response",
                   description: "Ctx variable that receives the string or parsed Hash. Default ai_response."
          end

          def generate_body
            attempt('"ai_inference.failed"', FlowchartRuntime::Ai::Error, FlowchartRuntime::Template::Error) do
              [
                "response = FlowchartRuntime::Ai.complete(ctx, #{complete_args})",
                assign(:resultVar, "response"),
                "response != false"
              ]
            end
          end

          private

          def complete_args
            [
              "prompt_template: #{read(:promptTemplate)}",
              ("model: #{read(:model)}" if value(:model).to_s.strip.present?),
              ("system_prompt: #{read(:systemPrompt)}" if value(:systemPrompt).to_s.strip.present?),
              ("max_tokens: #{read(:maxTokens)}" unless value(:maxTokens) == 1024),
              ("temperature: #{read(:temperature)}" unless value(:temperature) == 0.7),
              ("output_format: #{read(:outputFormat)}" unless value(:outputFormat).to_s == "text"),
              ("json_repair: #{read(:jsonRepair)}" if value(:jsonRepair)),
              ("on_invalid_json: #{read(:onInvalidJson)}" unless value(:onInvalidJson).to_s == "fail")
            ].compact.join(", ")
          end
        end
      end
    end
  end
end
