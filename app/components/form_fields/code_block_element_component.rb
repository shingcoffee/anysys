# frozen_string_literal: true

module FormFields
  class CodeBlockElementComponent < BaseElementComponent
    attr_reader :content_text, :code_language

    def initialize(content_text:, code_language: "", theme: {})
      super(theme: theme)
      @content_text = content_text
      @code_language = code_language
    end

    def language_present?
      code_language.present?
    end
  end
end
