# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Validation
        class FailWithErrorGenerator < BaseGenerator
          CODE_FORMAT = /\A[a-z][a-z0-9_]*\z/
          MAPPING_NAME = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

          generator_metadata do
            description "Ends the run on the failure track with a localized message shown in the public flash. Use this for a business refusal after a decision (not eligible, quota exceeded). Use validate_value or validate_contract for field-format checks, and set_submission_outcome for a successful flash. Reads message (localized_text) and optional errorField, errorCode, messageVariables. Writes ctx[:errors] and ctx[:error_details] through Step.fail_message. Always returns false so Trailblazer takes the failure track."
            category :validation
            version "2.0.0"
            presentation icon: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z",
                        color: "red", single_use: false, privileged: false
          end

          config_schema do
            localized_text :message, required: true, example: { "en" => "Not eligible", "zh-CN" => "不符合条件。" },
                           description: "Localized error shown in the public flash. Hash of locale to text, such as {\"en\" => \"Not eligible\", \"zh-CN\" => \"Not eligible.\"}. Named placeholders such as %{used} are filled from messageVariables."
            literal :errorField, default: "", placeholder: true,
                    description: "Optional form field slug to highlight on the public page, such as email or quantity. Leave blank for a page-level flash only. Must be a plain identifier."
            literal :errorCode, default: "business_error", example: "business_error", group: :advanced,
                    description: "Machine-readable code stored on ctx[:error_details], such as quota_exceeded. Later steps and the submitter can branch on it. Default business_error. Lowercase letters, digits, and underscores."
            mapping :messageVariables, key: :literal, value: :expression, default: [], group: :advanced,
                    description: "Named placeholders interpolated into message. Each key is a placeholder name (used) and each value is a Ruby expression over ctx (ctx[:used]). Missing names are left as %{name}."
            validate do |cfg, errors|
              name = cfg["errorField"].to_s.strip
              errors.add(:errorField, :invalid_identifier) unless name.empty? || ConfigSchema::IDENT_SEGMENT.match?(name)

              code = cfg["errorCode"].to_s.strip
              next if code.empty? || CODE_FORMAT.match?(code)

              errors.add(:errorCode, :invalid_identifier)
            end
          end

          def generate_body
            args = [read(:message).to_s]
            code = value(:errorCode).to_s.strip
            args << "code: #{read(:errorCode)}" unless code.empty? || code == "business_error"
            field = value(:errorField).to_s.strip
            args << "field: #{field.inspect}" if field.present?
            mapping = expression_mapping(:messageVariables)
            args << "variables: #{mapping}" if mapping != "{}"
            body("FlowchartRuntime::Step.fail_message(ctx, #{args.join(', ')})")
          end

          private

          def expression_mapping(field_name)
            pairs = Array(value(field_name)).filter_map do |row|
              next unless row.is_a?(Hash)

              name = (row["key"] || row[:key]).to_s
              expression = (row["value"] || row[:value]).to_s.strip
              next unless name.match?(MAPPING_NAME) && expression.present? && safe_expression?(expression)

              "#{name.inspect} => #{emit_expression(expression)}"
            end
            "{#{pairs.join(', ')}}"
          end
        end
      end
    end
  end
end
