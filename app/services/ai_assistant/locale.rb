# frozen_string_literal: true

module AiAssistant
  # UI locale for a signed-in assistant turn (same chain as SetLocale for a
  # signed-in user). Not the module's `language` setting, which only steers
  # transcription.
  class Locale
    def self.for(user:, customer:)
      [ user&.locale, customer&.locale ].each do |value|
        next if value.blank?

        match = I18n.available_locales.find { |locale| locale.to_s == value.to_s }
        return match.to_sym if match
      end
      I18n.default_locale
    end
  end
end
