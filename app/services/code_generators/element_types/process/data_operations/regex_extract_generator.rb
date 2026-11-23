# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class RegexExtractGenerator < BaseGenerator
          OPERATIONS = FlowchartRuntime::Regex::OPERATIONS
          FLAGS = FlowchartRuntime::Regex::FLAGS
          RETURN_TYPES = FlowchartRuntime::Regex::RETURN_TYPES

          generator_metadata do
            description "Extracts, tests, or replaces text with a timeout-bounded regular expression " \
                        "(Regexp.timeout, 1s) so a catastrophic pattern cannot hang the run. Reads " \
                        "sourceVariable. Writes resultVar: a capture string, an array of scans, a boolean " \
                        "test, or the replaced string. Use string_manipulate for trim, case, slug, pad, " \
                        "and literal replace, and validate_value for a whole-value pattern check. Fails " \
                        "with regex_extract.failed on an invalid pattern or a timeout."
            category :data_operations
            version "1.1.0"
            presentation icon: "M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z",
                         color: "pink", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "invoice_number",
              description: "Context path of the text to search (e.g. params.invoice_number)."
            output :resultVar, default: "match",
              description: "Context variable that receives the match, scan list, boolean test, or replaced text."
            literal :pattern, required: true, example: "(\\d+)", placeholder: true,
              description: "Ruby regular expression source, without wrapping slashes. Example: (\\d+) to capture digits. Max 4096 bytes."
            enum :operation, OPERATIONS, default: "match",
              description: "match returns one capture; scan returns every match; test writes true or false; " \
                           "replace substitutes every match with replacement."
            enum :flags, FLAGS, default: "none",
              description: "One Ruby regexp flag: none, i (ignore case), m (multiline, dot matches newline), or x (extended comments)."
            literal :regexFlags, default: "", placeholder: true, group: :advanced,
              description: "Combination of i, m, x, n flag letters that overrides flags when set. Example: im. Leave blank to use flags."
            enum :returnType, RETURN_TYPES, default: "first", visible: { operation: "match" },
              description: "What match keeps: first is captureGroup of the first match; all is every match (like scan); " \
                           "named_hash is named captures as a Hash."
            integer :captureGroup, min: 0, max: 99, default: 0, visible: { returnType: "first" },
              description: "Capture index for returnType first. 0 is the whole match; 1 is the first parenthesis group."
            literal :replacement, default: "", placeholder: true, visible: { operation: "replace" },
              description: "Replacement text for replace. May include \\1-style backreferences. Example: [REDACTED]."
            expression :fallbackValue, default: "nil", placeholder: true, visible: { operation: "match" },
              description: "Ruby expression written when match finds nothing (e.g. nil, \"\", or {}). Ignored for scan, test, and replace."
            requires :replacement, when: { operation: "replace" }

            validate do |_cfg, errors|
              pattern = value(:pattern)
              next if pattern.blank?

              FlowchartRuntime::Regex.compile(pattern, flags: value(:flags), regex_flags: value(:regexFlags))
            rescue FlowchartRuntime::Regex::Error
              errors.add(:pattern, :invalid_pattern)
            end
          end

          def generate_body
            body(
              attempt('"regex_extract.failed"', FlowchartRuntime::Regex::Error) do
                [
                  assign(:resultVar, regex_call),
                  "true"
                ]
              end
            )
          end

          private

          def regex_call
            "FlowchartRuntime::Regex.apply(#{regex_args})"
          end

          def regex_args
            op = value(:operation).to_s
            args = [read(:sourceVariable), "pattern: #{read(:pattern)}"]
            args << "operation: #{read(:operation)}" unless op == "match"
            args << "flags: #{read(:flags)}" unless value(:flags) == "none"
            args << "regex_flags: #{read(:regexFlags)}" unless value(:regexFlags).to_s.empty?
            if op == "match"
              args << "return_type: #{read(:returnType)}" unless value(:returnType) == "first"
              args << "capture_group: #{read(:captureGroup)}" unless value(:captureGroup).to_i.zero?
              args << "fallback: #{read(:fallbackValue)}" unless fallback_is_nil?
            end
            args << "replacement: #{read(:replacement)}" if op == "replace" && value(:replacement).to_s.present?
            args.join(", ")
          end

          def fallback_is_nil?
            raw = value(:fallbackValue).to_s.strip
            raw.empty? || raw == "nil"
          end
        end
      end
    end
  end
end
