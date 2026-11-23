# frozen_string_literal: true

module FormFields
  class BaseElementComponent < ApplicationComponent
    include ThemeResolver

    def initialize(theme: {})
      @theme = theme
    end

    protected

    def theme
      @theme
    end

    def accent
      resolve_accent_palette(@theme)
    end

    def palette
      color_palette(@theme)
    end

    def neutral(key)
      ThemeResolver::ELEMENT_NEUTRALS.fetch(key)
    end

    # Shared text-alignment helper (left/center/right → text-* classes).
    # Components that align *blocks* with flex justify classes must keep their own map.
    def alignment_class(alignment)
      case alignment
      when "center" then "text-center"
      when "right"  then "text-right"
      else "text-left"
      end
    end
  end
end
