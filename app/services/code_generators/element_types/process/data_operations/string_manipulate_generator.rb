# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class StringManipulateGenerator < BaseGenerator
          OPERATIONS = FlowchartRuntime::Text::OPERATIONS
          DELIM_OPS = %w[split join].freeze
          LENGTH_OPS = %w[pad_left pad_right truncate mask_middle].freeze
          REPLACE_OPS = %w[replace gsub].freeze
          BASE64_OPS = %w[base64_encode base64_decode].freeze

          generator_metadata do
            description "Transforms one string: strip or squish whitespace, change case, parameterize a slug, " \
                        "truncate, pad, split, join, replace or gsub, mask the middle for PII, HTML escape or " \
                        "unescape, and Base64 encode or decode. Reads sourceVariable. Writes resultVar. Use " \
                        "regex_extract for captures and tests, and format_value for locale display. Fails with " \
                        "string_manipulate.failed on an invalid gsub pattern or undecodable Base64."
            category :data_operations
            version "2.0.0"
            presentation icon: "M3 5h12M9 3v2m1.048 9.5A18.022 18.022 0 016.412 9m6.088 9h7M11 21l5-10 5 10M12.751 5C11.783 10.77 8.07 15.61 3 18.129",
                         color: "cyan", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "customer_name",
              description: "Context path of the string (or array for join) to transform (e.g. params.customer_name)."
            output :resultVar, default: "text",
              description: "Context variable that receives the transformed string or, for split, the array of parts."
            enum :operation, OPERATIONS, default: "strip",
              description: "Transform to apply. strip trims ends; squish collapses inner space; parameterize is a URL slug; " \
                           "mask_middle hides the middle of a PAN or ID; gsub replaces every pattern match."
            flag :regexEscape, default: false, visible: { operation: "gsub" },
              description: "Treat the gsub pattern as a literal string (Regexp.escape) instead of a regular expression."
            literal :delimiter, default: ",", placeholder: true, visible: { operation: DELIM_OPS },
              description: "Separator for split and join. Example: , or | . Default is a comma."
            integer :length, min: 1, max: 10_000, default: 10, visible: { operation: LENGTH_OPS },
              description: "Target length for pad and truncate, or how many characters to keep at each end for mask_middle. Example: 4."
            literal :padChar, default: " ", placeholder: true, visible: { operation: %w[pad_left pad_right mask_middle] },
              description: "Fill character for pad, or the mask character for mask_middle (default space; use * for cards)."
            literal :pattern, default: "", placeholder: true, visible: { operation: REPLACE_OPS },
              description: "Search text for replace (first match) or gsub (every match). Example: - or \\s+."
            literal :replacement, default: "", placeholder: true, visible: { operation: REPLACE_OPS },
              description: "Replacement text for replace and gsub. Blank deletes the matched text."
            flag :urlSafe, default: false, visible: { operation: BASE64_OPS },
              description: "Use the URL-safe Base64 alphabet (- and _) instead of + and /."
            requires :pattern, when: { operation: REPLACE_OPS }
          end

          def generate_body
            body(
              attempt('"string_manipulate.failed"', FlowchartRuntime::Text::Error) do
                [
                  assign(:resultVar, text_call),
                  "true"
                ]
              end
            )
          end

          private

          def text_call
            "FlowchartRuntime::Text.apply(#{text_args})"
          end

          def text_args
            op = value(:operation).to_s
            args = [read(:sourceVariable), "operation: #{read(:operation)}"]
            args << "delimiter: #{read(:delimiter)}" if DELIM_OPS.include?(op) && value(:delimiter) != ","
            if LENGTH_OPS.include?(op)
              args << "length: #{read(:length)}" unless value(:length) == 10
            end
            if %w[pad_left pad_right mask_middle].include?(op)
              args << "pad_char: #{read(:padChar)}" unless value(:padChar) == " "
            end
            if REPLACE_OPS.include?(op)
              args << "pattern: #{read(:pattern)}" unless value(:pattern).to_s.empty?
              args << "replacement: #{read(:replacement)}" unless value(:replacement).to_s.empty?
              args << "regex_escape: true" if op == "gsub" && value(:regexEscape)
            end
            args << "url_safe: true" if BASE64_OPS.include?(op) && value(:urlSafe)
            args.join(", ")
          end
        end
      end
    end
  end
end
