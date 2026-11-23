# frozen_string_literal: true

module FlowchartRuntime
  # I18n lookup for the i18n_translate step. Lives here so generated bodies
  # never contain I18n.t (BodyLint).
  module Translate
    class Error < StandardError; end

    module_function

    def call(key, locale: nil, fallback_locale: nil, interpolations: {},
             scope: nil, default: nil, count: nil, raise_on_missing: false)
      options = interpolation_hash(interpolations)
      options[:locale] = locale_value(locale) unless locale_value(locale).nil?
      options[:scope] = scope if scope.to_s.present?
      options[:default] = default if default.to_s.present?
      options[:count] = count unless count.nil?

      lookup(key.to_s, options, bang: raise_on_missing)
    rescue I18n::MissingTranslationData, Error
      raise Error, "missing translation" if fallback_locale.to_s.strip.empty?

      lookup(key.to_s, options.merge(locale: locale_value(fallback_locale)), bang: true)
    end

    def lookup(key, options, bang:)
      bang ? I18n.t!(key, **options) : I18n.t(key, **options)
    rescue I18n::MissingTranslationData
      raise Error, "missing translation" if bang

      raise
    end

    def locale_value(locale)
      return nil if locale.nil? || locale.to_s.strip.empty? || locale.to_s == "I18n.locale"

      locale
    end

    def interpolation_hash(raw)
      return {} unless raw.is_a?(Hash)

      raw.each_with_object({}) do |(key, value), memo|
        name = key.to_s
        next unless name.match?(/\A[a-z_][a-zA-Z0-9_]*\z/)

        memo[name.to_sym] = value
      end
    end
  end
end
