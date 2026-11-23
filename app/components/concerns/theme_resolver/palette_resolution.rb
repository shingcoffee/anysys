# frozen_string_literal: true

module ThemeResolver
  # Resolves color-palette-based CSS classes: primary colour, accent palette,
  # form background.  All methods are pure functions of the theme hash and the
  # COLOR_PALETTES / ACCENT_PALETTES / FORM_BG_MAP constants defined on the
  # parent ThemeResolver module.
  module PaletteResolution
    private

    def color_palette(theme)
      ThemeResolver::COLOR_PALETTES[resolve_theme(theme)["primary_color"]] ||
        ThemeResolver::COLOR_PALETTES["indigo"]
    end

    def resolve_form_bg(theme)
      ThemeResolver::FORM_BG_MAP[resolve_theme(theme)["form_background"]] ||
        ThemeResolver::FORM_BG_MAP["white"]
    end

    def resolve_accent_palette(theme)
      resolved = resolve_theme(theme)
      ThemeResolver::ACCENT_PALETTES[resolved["accent_color"]] ||
        ThemeResolver::ACCENT_PALETTES["indigo"]
    end
  end
end
