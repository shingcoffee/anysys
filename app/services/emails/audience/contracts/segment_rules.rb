# frozen_string_literal: true

module Emails
  module Audience
    module Contracts
      class SegmentRules < Reform::Form
        MAX_JSON_BYTES = 64.kilobytes
        Input = Struct.new(:rules)

        property :rules
        validate :tree_is_valid

        # Both preview and writes use the same bounded JSON/semantic validation.
        # An omitted or blank editor field intentionally requests an empty root.
        def self.from_json(raw)
          form = new(Input.new)
          rules = if raw.nil?
                    {}
                  elsif raw.is_a?(String) && raw.bytesize <= MAX_JSON_BYTES
                    raw.blank? ? {} : JSON.parse(raw)
                  end
          form.validate(rules: rules)
          form
        rescue JSON::ParserError
          form.validate(rules: nil)
          form
        end

        private

        def tree_is_valid
          return if SegmentQuery.valid?(rules)

          errors.add(:rules, I18n.t("admin_modules.errors.lists.segment_malformed"))
        end
      end
    end
  end
end
