# frozen_string_literal: true

module FormFields
  class CalloutElementComponent < BaseElementComponent
    attr_reader :content_text

    def initialize(content_text:, theme: {})
      super(theme: theme)
      @content_text = content_text
    end
  end
end
