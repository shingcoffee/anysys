# frozen_string_literal: true

module Operations
  class Violation < Struct.new(:pointer, :code, :details, :resolution, keyword_init: true)
    RESOLUTIONS = %w[fix_payload ask_user refresh blocked].freeze
    MAX_CANDIDATES = 3

    def initialize(pointer: "", code:, details: {}, resolution: nil)
      super(
        pointer: pointer.to_s,
        code: code.to_s,
        details: stringify_keys(details || {}),
        resolution: (resolution.presence || default_resolution(code)).to_s
      )
    end

    def message
      key = "operations.violations.#{code}"
      text = if I18n.exists?(key)
        I18n.t(key, **interpolation_values)
      else
        I18n.t("operations.violations.generic", code: code)
      end
      suggestions = Array(details["candidates"]).compact_blank
      return text if suggestions.empty?

      text + I18n.t("operations.violations.did_you_mean", candidates: suggestions.join(", "))
    end

    def as_json(*)
      {
        "pointer" => pointer,
        "code" => code,
        "message" => message,
        "resolution" => resolution
      }.merge(json_safe_details)
    end

    def self.candidates(word, dictionary)
      list = Array(dictionary).map(&:to_s)
      return [] if word.blank? || list.empty?

      exact = list.select { |item| item.casecmp?(word.to_s) }
      return exact.first(MAX_CANDIDATES) if exact.any?

      DidYouMean::SpellChecker.new(dictionary: list).correct(word.to_s).first(MAX_CANDIDATES)
    end

    private

    def default_resolution(code)
      name = code.to_s
      return "blocked" if name.start_with?("permission.", "quota.")
      return "refresh" if name.start_with?("conflict.")

      "fix_payload"
    end

    def interpolation_values
      details.each_with_object({}) do |(key, value), acc|
        acc[key.to_sym] = case value
        when Array then value.join(", ")
        when Hash then next
        else value
        end
      end
    end

    def json_safe_details
      details.each_with_object({}) do |(key, value), acc|
        acc[key.to_s] = value if json_safe?(value)
      end
    end

    def json_safe?(value)
      case value
      when NilClass, TrueClass, FalseClass, Numeric, String then true
      when Array then value.all? { |item| json_safe?(item) }
      when Hash then value.all? { |k, v| (k.is_a?(String) || k.is_a?(Symbol)) && json_safe?(v) }
      else false
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) { |(key, value), acc| acc[key.to_s] = value }
    end
  end
end
