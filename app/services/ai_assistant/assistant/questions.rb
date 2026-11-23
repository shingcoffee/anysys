# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Untrusted model output for structured clarification. Drops anything it
    # cannot use; never fails a turn.
    class Questions
      MAX_QUESTIONS = 5
      MAX_OPTIONS = 8
      MAX_PROMPT_LENGTH = 300
      MAX_OPTION_LENGTH = 80
      MAX_TEXT_DEFAULT_LENGTH = 300
      MAX_ASSUMPTIONS = 5
      MAX_ASSUMPTION_LENGTH = 200
      TYPES = %w[single multiple text].freeze
      ELLIPSIS = "…"

      class << self
        def sanitize(raw)
          return [] unless raw.is_a?(Array)

          raw.filter_map { |item| sanitize_item(item) }
             .first(MAX_QUESTIONS)
             .map.with_index(1) { |item, index| { "id" => "q#{index}" }.merge(item) }
        rescue StandardError
          []
        end

        def sanitize_assumptions(raw)
          values = case raw
                   when String then [raw]
                   when Array then raw
                   else return []
                   end
          unique_clipped(values, MAX_ASSUMPTION_LENGTH, MAX_ASSUMPTIONS)
        rescue StandardError
          []
        end

        private

        def sanitize_item(item)
          return unless item.is_a?(Hash)

          item = item.stringify_keys
          prompt = clip(item["prompt"], MAX_PROMPT_LENGTH)
          return if prompt.blank?

          options = sanitize_options(item["options"])
          type = normalize_type(item["type"], options)
          default = item["default"]
          if %w[single multiple].include?(type) && options.size < 2
            type = "text"
            default = leftover_text_default(default, options)
          end

          {
            "prompt" => prompt,
            "type" => type,
            "options" => type == "text" ? [] : options,
            "default" => resolve_default(type, default, options)
          }
        end

        def sanitize_options(raw)
          return [] unless raw.is_a?(Array)

          seen = {}
          kept = []
          raw.each do |value|
            next unless value.is_a?(String)

            text = value.squish
            next if text.blank? || text.length > MAX_OPTION_LENGTH

            key = text.downcase
            next if seen[key]

            seen[key] = true
            kept << text
            break if kept.size == MAX_OPTIONS
          end
          kept
        end

        def normalize_type(type, options)
          return type if TYPES.include?(type)

          options.size >= 2 ? "single" : "text"
        end

        def leftover_text_default(default, options)
          usable_text_default?(default) ? default : options.first
        end

        def usable_text_default?(value)
          value.is_a?(String) && value.squish.present?
        end

        def resolve_default(type, default, options)
          case type
          when "single" then canonical_option(default, options)
          when "multiple" then multiple_default(default, options)
          else clip(default, MAX_TEXT_DEFAULT_LENGTH).presence
          end
        end

        def multiple_default(default, options)
          values = case default
                   when Array then default
                   when String then [default]
                   else []
                   end
          seen = {}
          values.each_with_object([]) do |value, kept|
            match = canonical_option(value, options)
            next unless match

            key = match.downcase
            next if seen[key]

            seen[key] = true
            kept << match
          end
        end

        def canonical_option(value, options)
          return unless value.is_a?(String)

          needle = value.squish
          return if needle.blank?

          options.find { |option| option.casecmp?(needle) }
        end

        def unique_clipped(values, limit, cap)
          seen = {}
          kept = []
          values.each do |value|
            text = clip(value, limit)
            next if text.blank?

            key = text.downcase
            next if seen[key]

            seen[key] = true
            kept << text
            break if kept.size == cap
          end
          kept
        end

        def clip(value, limit)
          return unless value.is_a?(String)

          value.squish.truncate(limit, omission: ELLIPSIS)
        end
      end
    end
  end
end
