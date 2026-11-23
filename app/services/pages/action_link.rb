# frozen_string_literal: true

module Pages
  # Builds every action URL; nil when the action key is malformed. Prefill
  # values that fail the query limits are dropped.
  class ActionLink
    MAX_PREFILL_KEYS = 10
    MAX_PREFILL_VALUE = 200

    def self.path(customer_id:, action_key:, prefill: {})
      return unless action_key.to_s.match?(PageVisibility::ACTION_KEY)

      query = sanitized_prefill(prefill)
      path = "/#{customer_id}/actions/#{action_key}"
      return path if query.empty?

      "#{path}?#{query.map { |slug, value| "prefill[#{slug}]=#{CGI.escape(value)}" }.join("&")}"
    end

    def self.sanitized_prefill(prefill)
      hash = prefill.respond_to?(:to_unsafe_h) ? prefill.to_unsafe_h : prefill.to_h
      hash.each_with_object({}) do |(key, value), kept|
        break kept if kept.size >= MAX_PREFILL_KEYS
        next if value.is_a?(Hash) || value.is_a?(Array)

        slug = key.to_s
        next unless slug.match?(FormParams::SLUG)

        text = value.to_s
        next if text.length > MAX_PREFILL_VALUE

        kept[slug] = text
      end
    end
  end
end
