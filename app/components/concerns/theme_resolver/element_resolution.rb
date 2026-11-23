# frozen_string_literal: true

module ThemeResolver
  # Resolves element-level CSS classes: input fields, labels, and buttons.
  # Depends on layout helpers (resolve_radius_class) and palette helpers
  # (color_palette) that are provided by the sibling sub-modules when all are
  # included together into ThemeResolver.
  module ElementResolution
    private

    def resolve_input_classes(theme)
      resolved = resolve_theme(theme)
      palette  = color_palette(theme)
      input_base = ThemeResolver::INPUT_STYLES[resolved["input_style"]] ||
                   ThemeResolver::INPUT_STYLES["outline"]
      radius = resolved["input_style"] == "underline" ? "" : resolve_radius_class(theme)
      size   = ThemeResolver::INPUT_SIZE_MAP[resolved["input_size"]] ||
               ThemeResolver::INPUT_SIZE_MAP["md"]

      "w-full #{size} #{input_base} #{radius} focus:outline-none focus:ring-2 " \
        "focus:ring-offset-2 #{palette[:ring_color]} #{palette[:border]} " \
        "focus:shadow-sm transition-all duration-150".squish
    end

    def resolve_label_classes(theme)
      ThemeResolver::LABEL_STYLE_MAP[resolve_theme(theme)["label_style"]] ||
        ThemeResolver::LABEL_STYLE_MAP["default"]
    end

    def resolve_button_style_classes(theme)
      resolved   = resolve_theme(theme)
      palette    = color_palette(theme)
      style_proc = ThemeResolver::BUTTON_STYLE_MAP[resolved["button_style"]]
      style_proc ? style_proc.call(palette) : ThemeResolver::BUTTON_STYLE_MAP["filled"].call(palette)
    end

    def resolve_button_width(theme)
      ThemeResolver::BUTTON_WIDTH_MAP[resolve_theme(theme)["button_width"]] ||
        ThemeResolver::BUTTON_WIDTH_MAP["full"]
    end

    def resolve_button_size(theme)
      ThemeResolver::BUTTON_SIZE_MAP[resolve_theme(theme)["button_size"]] ||
        ThemeResolver::BUTTON_SIZE_MAP["md"]
    end

    def resolve_submit_button_classes(theme)
      radius = resolve_radius_class(theme)

      [
        resolve_button_style_classes(theme),
        resolve_button_width(theme),
        resolve_button_size(theme),
        radius,
        "transition-all duration-200 focus:ring-2 focus:ring-offset-2 font-medium",
        "disabled:opacity-50 disabled:cursor-not-allowed mt-6"
      ].reject(&:blank?).join(" ").squish
    end
  end
end
