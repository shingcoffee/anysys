# frozen_string_literal: true

module ThemeResolver
  # Resolves preset-keyed CSS classes: page-chrome backgrounds, header/desc
  # colours, card wrappers, and section border/legend styling.  All methods
  # operate by first detecting whether the supplied theme hash is an exact match
  # for one of the named presets, then falling back to hue or generic defaults.
  module PresetResolution
    private

    def detect_preset(theme)
      resolved = resolve_theme(theme)
      ThemeResolver::THEME_PRESETS.each do |name, preset|
        return name if preset.all? { |key, value| resolved[key] == value }
      end
      nil
    end

    def resolve_page_chrome_bg(theme)
      preset = detect_preset(theme)
      return ThemeResolver::PAGE_CHROME_BG_MAP[preset] if preset

      ThemeResolver::PAGE_CHROME_BG_BY_HUE[resolve_theme(theme)["primary_color"]] || "bg-gray-50"
    end

    def resolve_page_chrome_header_color(theme)
      ThemeResolver::PAGE_CHROME_HEADER_MAP[detect_preset(theme)] || "text-gray-900"
    end

    def resolve_page_chrome_desc_color(theme)
      ThemeResolver::PAGE_CHROME_DESC_MAP[detect_preset(theme)] || "text-gray-500"
    end

    def resolve_page_chrome_card(theme)
      card = ThemeResolver::PAGE_CHROME_CARD_MAP[detect_preset(theme)]
      card.nil? ? "rounded-xl overflow-hidden" : card
    end

    def resolve_section_border(theme)
      preset = detect_preset(theme)
      preset ? (ThemeResolver::SECTION_BORDER_MAP[preset] || "") : ""
    end

    def resolve_section_legend_extra(theme)
      preset = detect_preset(theme)
      preset ? (ThemeResolver::SECTION_LEGEND_EXTRA_MAP[preset] || "") : ""
    end
  end
end
