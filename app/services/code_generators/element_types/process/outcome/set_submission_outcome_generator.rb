# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Outcome
        class SetSubmissionOutcomeGenerator < BaseGenerator
          PRESETS = %w[submitted saved thank_you custom].freeze
          FLASHES = %w[notice alert].freeze
          MAPPING_NAME = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

          generator_metadata do
            description "Sets the public flash after a successful submit: preset copy (submitted, saved, thank_you) or a custom localized message, with notice or alert styling. This step does not choose a destination; use hand_off_to_module or request_payment (and their exitKind) to send the visitor somewhere, and skip_journey_steps to leave later journey steps out. Those writes live on ctx[:submission_outcome] and this step preserves handoff and journey keys already parked there, so run it before or after them without clobbering. Writes ctx[:submission_outcome] preset, message, and flash."
            category :outcome
            version "1.2.0"
            presentation icon: "M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z",
                        color: "teal", single_use: false, privileged: false
          end

          config_schema do
            enum :preset, PRESETS, default: "submitted",
                 description: "Standard thank-you copy shown after submit: submitted, saved, or thank_you. custom uses the localized message field instead (required when custom)."
            localized_text :message, example: { "en" => "Thank you.", "zh-CN" => "谢谢。" },
                           description: "Localized flash text. Required when preset is custom; optional extra copy for the other presets. Hash of locale to text. Named placeholders such as %{name} are filled from messageVariables."
            enum :flash, FLASHES, default: "notice",
                 description: "Banner style shown after a successful submit. notice is the default success banner; alert is a warning-style banner."
            mapping :messageVariables, key: :literal, value: :expression, default: [], group: :advanced,
                    description: "Named placeholders interpolated into message. Each key is a placeholder name (name) and each value is a Ruby expression over ctx (ctx[:name]). Applied to every locale of the stored message."
            requires :message, when: { preset: "custom" }
          end

          def generate_body
            body(
              "outcome = (ctx[:submission_outcome] || {}).stringify_keys",
              "payload = { \"preset\" => #{read(:preset)}, \"message\" => #{message_expr}, \"flash\" => #{read(:flash)} }",
              "payload[\"handoff\"] = outcome[\"handoff\"] if outcome[\"handoff\"]",
              "payload[\"journey\"] = outcome[\"journey\"] if outcome[\"journey\"]",
              "ctx[:submission_outcome] = payload"
            )
          end

          private

          def message_expr
            raw = value(:message)
            base = raw.present? ? read(:message) : "nil"
            mapping = expression_mapping(:messageVariables)
            return base if mapping == "{}"

            "FlowchartRuntime::LocalizedText.interpolate_each(#{base}, #{mapping})"
          end

          def expression_mapping(field_name)
            pairs = safe_expression_pairs(value(field_name)).filter_map do |name, expression|
              next unless name.match?(MAPPING_NAME)

              "#{literal(name)} => #{emit_expression(expression)}"
            end
            return "{}" if pairs.empty?

            "{#{pairs.join(', ')}}"
          end
        end
      end
    end
  end
end
