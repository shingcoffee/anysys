# frozen_string_literal: true

module FormFields
  class ParagraphElementComponent < BaseElementComponent
    attr_reader :content_text, :alignment

    def initialize(content_text:, alignment: "left", theme: {})
      super(theme: theme)
      @content_text = content_text
      @alignment = alignment
    end
  end
end
