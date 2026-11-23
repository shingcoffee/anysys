# frozen_string_literal: true

module ThemeResolver
  # Resolves layout and spacing CSS classes: border-radius, font family, form
  # container dimensions (width/shadow/padding/border), field spacing rhythm,
  # and section/divider/heading margins.  All methods are pure functions of the
  # theme hash and the map constants defined on the parent ThemeResolver module.
  module LayoutResolution
    private

    def resolve_font_class(theme)
      ThemeResolver::FONT_MAP[resolve_theme(theme)["font_family"]] ||
        ThemeResolver::FONT_MAP["sans"]
    end

    def resolve_radius_class(theme)
      ThemeResolver::RADIUS_MAP[resolve_theme(theme)["border_radius"]] ||
        ThemeResolver::RADIUS_MAP["lg"]
    end

    def resolve_container_radius_class(theme)
      ThemeResolver::CONTAINER_RADIUS_MAP[resolve_theme(theme)["border_radius"]] ||
        ThemeResolver::CONTAINER_RADIUS_MAP["lg"]
    end

    def resolve_form_width(theme)
      ThemeResolver::FORM_WIDTH_MAP[resolve_theme(theme)["form_width"]] ||
        ThemeResolver::FORM_WIDTH_MAP["xl"]
    end

    def resolve_form_shadow(theme)
      ThemeResolver::FORM_SHADOW_MAP[resolve_theme(theme)["form_shadow"]] ||
        ThemeResolver::FORM_SHADOW_MAP["none"]
    end

    def resolve_form_padding(theme)
      ThemeResolver::FORM_PADDING_MAP[resolve_theme(theme)["form_padding"]] ||
        ThemeResolver::FORM_PADDING_MAP["normal"]
    end

    def resolve_form_border(theme)
      ThemeResolver::FORM_BORDER_MAP[resolve_theme(theme)["form_border"]] ||
        ThemeResolver::FORM_BORDER_MAP["none"]
    end

    def resolve_field_spacing(theme)
      ThemeResolver::FIELD_SPACING_MAP[resolve_theme(theme)["field_spacing"]] ||
        ThemeResolver::FIELD_SPACING_MAP["normal"]
    end

    def resolve_section_top_margin(theme)
      spacing = resolve_theme(theme)["field_spacing"] || "normal"
      ThemeResolver::SECTION_SPACING_MAP.dig(spacing, :mt) || "mt-6"
    end

    def resolve_section_bottom_margin(theme)
      spacing = resolve_theme(theme)["field_spacing"] || "normal"
      ThemeResolver::SECTION_SPACING_MAP.dig(spacing, :mb) || "mb-2.5"
    end

    def resolve_divider_spacing(theme)
      spacing = resolve_theme(theme)["field_spacing"] || "normal"
      ThemeResolver::DIVIDER_SPACING_MAP[spacing] || "my-5"
    end

    def resolve_heading_top_margin(theme)
      spacing = resolve_theme(theme)["field_spacing"] || "normal"
      ThemeResolver::HEADING_TOP_MARGIN_MAP[spacing] || "mt-3"
    end
  end
end
