# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class SanitizeInputGenerator < BaseGenerator
          SANITIZERS = FlowchartRuntime::Sanitize::SANITIZERS
          OVERFLOW = FlowchartRuntime::Sanitize::OVERFLOW
          TAG_RE = /\A[a-zA-Z][a-zA-Z0-9-]*\z/
          ATTRIBUTE_RE = /\A[a-zA-Z_:][a-zA-Z0-9_:.-]*\z/

          generator_metadata do
            description "Sanitizes sourceVariable HTML/text and writes the safe string to resultVar. strip_tags " \
                        "(default) uses Rails FullSanitizer; escape_html uses ERB::Util.html_escape for display; " \
                        "rails is SafeListSanitizer with allowedTags/allowedAttributes. Use this before storing " \
                        "or rendering visitor copy. Fails with sanitize_input.failed when onOverflow is fail."
            category :security
            version "3.0.0"
            presentation icon: "M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z",
                          color: "red", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "user_input",
                  description: "Context path of the submitted text, e.g. user_input or comment_body."
            output :resultVar, default: "sanitized",
                   description: "Ctx key that receives the sanitized string. Default sanitized."
            enum :sanitizer, SANITIZERS, default: "strip_tags",
                 description: "strip_tags: drop every HTML tag (Rails FullSanitizer). escape_html: escape <>& " \
                              "for safe display. rails: keep only allowedTags and allowedAttributes via " \
                              "SafeListSanitizer."
            list :allowedTags, item: :literal, example: %w[b i], visible: { sanitizer: "rails" },
                 description: "Tag names the rails sanitizer may keep, e.g. b, i, a. Empty keeps none. " \
                              "Letters, digits, and hyphens only."
            list :allowedAttributes, item: :literal, example: %w[href], visible: { sanitizer: "rails" },
                 description: "Attribute names the rails sanitizer may keep, e.g. href. Empty keeps none."
            flag :removeNullBytes, default: true,
                 description: "When true (default), delete NUL bytes before sanitizing. Turn off only when a " \
                              "caller must preserve them."
            integer :maxLength, min: 0, default: 0,
                    description: "Maximum character length after sanitizing. 0 (default) means no limit. " \
                                 "Example: 2000. onOverflow decides what happens when longer."
            enum :onOverflow, OVERFLOW, default: "truncate", group: :advanced,
                 description: "When maxLength is positive and the text is longer: truncate (default, String#truncate) " \
                              "or fail the step with sanitize_input.failed."
            flag :trimWhitespace, default: false, group: :advanced,
                 description: "When true, strip leading and trailing whitespace after sanitizing. Default false."
            validate do |cfg, errors|
              next unless cfg["sanitizer"].to_s == "rails"

              bad_tags = Array(cfg["allowedTags"]).map(&:to_s).reject { |tag| tag.match?(TAG_RE) }
              errors.add(:allowedTags, :invalid_tags, entries: bad_tags.join(", ")) if bad_tags.any?
              bad_attrs = Array(cfg["allowedAttributes"]).map(&:to_s).reject { |attr| attr.match?(ATTRIBUTE_RE) }
              errors.add(:allowedAttributes, :invalid_attributes, entries: bad_attrs.join(", ")) if bad_attrs.any?
            end
          end

          def generate_body
            body(
              attempt('"sanitize_input.failed"', FlowchartRuntime::Sanitize::Error) do
                [
                  assign(:resultVar, "FlowchartRuntime::Sanitize.apply(#{sanitize_args})"),
                  "true"
                ]
              end
            )
          end

          private

          def sanitize_args
            sanitizer = value(:sanitizer).to_s
            parts = [read(:sourceVariable), "sanitizer: #{read(:sanitizer)}"]
            if sanitizer == "rails"
              tags = Array(value(:allowedTags))
              parts << "tags: #{read(:allowedTags)}" if tags.any?
              attrs = Array(value(:allowedAttributes))
              parts << "attributes: #{read(:allowedAttributes)}" if attrs.any?
            end
            parts << "remove_null_bytes: false" unless value(:removeNullBytes)
            parts << "max_length: #{read(:maxLength)}" unless value(:maxLength).to_i.zero?
            overflow = value(:onOverflow).to_s
            parts << "on_overflow: #{read(:onOverflow)}" unless overflow.empty? || overflow == "truncate"
            parts << "trim_whitespace: true" if value(:trimWhitespace)
            parts.join(", ")
          end
        end
      end
    end
  end
end
