# frozen_string_literal: true

module FormFields
  class ImageElementComponent < BaseElementComponent
    attr_reader :image_url, :alt_text, :alignment

    def initialize(image_url:, alt_text: "", alignment: "center", theme: {})
      super(theme: theme)
      @image_url = image_url
      @alt_text = alt_text
      @alignment = alignment
    end

    def image_present?
      image_url.present?
    end
  end
end
