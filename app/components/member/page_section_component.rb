# frozen_string_literal: true

module Member
  # Hairline card in the public-site theme. density :default keeps the
  # card padding, :compact tightens it, :flush removes it for tables.
  class PageSectionComponent < ApplicationComponent
    include UsesSiteChrome
    DENSITY_CLASSES = {
      default: "",
      compact: "p-5",
      flush:   "p-0 overflow-hidden"
    }.freeze

    def initialize(title: nil, description: nil, density: :default)
      unless DENSITY_CLASSES.key?(density)
        raise ArgumentError, "unknown density: #{density.inspect} (expected #{DENSITY_CLASSES.keys.inspect})"
      end

      @title       = title
      @description = description
      @density     = density
    end

    attr_reader :title, :description, :density

    def section_classes
      chrome.card_class(density)
    end
  end
end
