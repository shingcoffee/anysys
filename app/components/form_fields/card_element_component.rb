# frozen_string_literal: true

module FormFields
  class CardElementComponent < BaseElementComponent
    attr_reader :title, :content_text

    def initialize(title:, content_text: "", theme: {})
      super(theme: theme)
      @title = title
      @content_text = content_text
    end

    def content_present?
      content_text.present?
    end
  end
end
