# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class MaskDataGenerator < BaseGenerator
          MASK_TYPES = FlowchartRuntime::Mask::TYPES
          FORMAT_TYPES = %w[phone mobile ssn credit_card id_number].freeze

          generator_metadata do
            description "Masks sourceVariable for logs or UI and writes the display string to resultVar. Use " \
                        "credit_card (PCI BIN+last4), email, phone, mobile (CN 11-digit first3+last4), ssn, " \
                        "id_number (CN resident ID first6+last4), name, address, last4, first1_last1, or full. " \
                        "custom uses regexPattern or visibleStart/visibleEnd. Fails with mask_data.failed."
            category :security
            version "2.2.0"
            presentation icon: "M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21",
                          color: "amber", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "credit_card",
                  description: "Context path of the value to mask, e.g. credit_card, email, or national_id."
            output :resultVar, default: "masked",
                   description: "Ctx key that receives the masked display string. Default masked."
            enum :maskType, MASK_TYPES, default: "last4",
                 description: "Preset: last4, first1_last1, email (keep local first char + domain), phone " \
                              "(last4 + +CC), mobile (first3+last4), ssn (last4), credit_card (BIN+last4), " \
                              "id_number (first6+last4), name, address, full. custom uses regex or windows."
            integer :visibleStart, min: 0, default: 0, visible: { maskType: "custom" },
                    description: "For custom with no regexPattern: significant characters kept at the start. " \
                                 "Default 0. Example: 3 with visibleEnd 4 on a mobile number."
            integer :visibleEnd, min: 0, default: 0, visible: { maskType: "custom" },
                    description: "For custom with no regexPattern: significant characters kept at the end. " \
                                 "Default 0. Example: 4."
            literal :maskChar, default: "*",
                    description: "Single character used to hide the masked portion. Default * . Example: X."
            flag :preserveFormat, default: true,
                 visible: { maskType: FORMAT_TYPES },
                 description: "When true (default), keep dashes/spaces on phone, mobile, ssn, credit_card, and " \
                              "id_number. When false, mask a digits-only (or alnum for id_number) compact form."
            literal :regexPattern, placeholder: true, visible: { maskType: "custom" },
                    description: "When set, each regex match is replaced with maskChar, e.g. \\d. When blank, " \
                                 "custom uses visibleStart/visibleEnd instead."
          end

          def generate_body
            body(
              attempt('"mask_data.failed"', FlowchartRuntime::Mask::Error) do
                [
                  assign(:resultVar, "FlowchartRuntime::Mask.apply(#{mask_args})"),
                  "true"
                ]
              end
            )
          end

          private

          def mask_args
            type = value(:maskType).to_s
            parts = [read(:sourceVariable), "type: #{read(:maskType)}"]
            parts << "mask_char: #{read(:maskChar)}" unless value(:maskChar).to_s == "*"
            if type == "custom"
              parts << "visible_start: #{read(:visibleStart)}" unless value(:visibleStart).to_i.zero?
              parts << "visible_end: #{read(:visibleEnd)}" unless value(:visibleEnd).to_i.zero?
            end
            parts << "preserve_format: false" if FORMAT_TYPES.include?(type) && !value(:preserveFormat)
            pattern = value(:regexPattern).to_s
            parts << "regex_pattern: #{read(:regexPattern)}" if type == "custom" && pattern.present?
            parts.join(", ")
          end
        end
      end
    end
  end
end
