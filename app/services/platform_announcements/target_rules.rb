# frozen_string_literal: true

module PlatformAnnouncements
  # Value object around the audience builder's JSON payload.
  #
  # The builder posts its tree as a JSON string in a hidden field, so parsing,
  # the "malformed input" signal, and the usability check all belong together
  # instead of being smeared across the save activity and the contract.
  class TargetRules
    EMPTY = {}.freeze

    class << self
      def parse(raw)
        return new(rules: raw.presence || EMPTY) if raw.is_a?(Hash)
        return new(rules: EMPTY) if raw.blank?

        new(rules: JSON.parse(raw.to_s))
      rescue JSON::ParserError, TypeError
        new(rules: EMPTY, malformed: true)
      end

      def empty = new(rules: EMPTY)
    end

    def initialize(rules:, malformed: false)
      @rules     = rules.is_a?(Hash) ? rules : EMPTY
      @malformed = malformed || !rules.is_a?(Hash) || !CustomerQuery.valid?(@rules)
    end

    attr_reader :rules

    def malformed? = @malformed

    def usable? = !malformed? && CustomerQuery.usable?(rules)

    def matching_customers
      return Customer.none unless usable?

      CustomerQuery.call(rules: rules).order(:name, :id)
    end
  end
end
