# frozen_string_literal: true

module Websites
  # A photo shown whole inside a section's image frame. The photo keeps its
  # aspect and never grows past its own pixels; a blurred copy fills the rest
  # of the frame. Used for photos placed by the AI assistant (see
  # Websites::ImageFit).
  class FittedPhotoComponent < PublicComponent
    FRAME_CLASSES = %w[flex items-center justify-center overflow-hidden].freeze

    def initialize(src:, alt: "", css_class: "", eager: false)
      @src = src
      @alt = alt
      @css_class = css_class
      @eager = eager
    end

    attr_reader :src, :alt

    # The section's own frame classes, minus the crop.
    def frame_class
      (@css_class.to_s.split - %w[object-cover] + FRAME_CLASSES).uniq.join(" ")
    end

    def loading
      @eager ? "eager" : "lazy"
    end
  end
end
