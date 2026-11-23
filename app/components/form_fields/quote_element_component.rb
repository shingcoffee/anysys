# frozen_string_literal: true

module FormFields
  class QuoteElementComponent < BaseElementComponent
    attr_reader :content_text, :attribution

    def initialize(content_text:, attribution: "", theme: {})
      super(theme: theme)
      @content_text = content_text
      @attribution = attribution
    end

    def attribution_present?
      attribution.present?
    end
  end
end
