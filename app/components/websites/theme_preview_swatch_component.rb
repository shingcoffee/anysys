# frozen_string_literal: true

module Websites
  # Mini hero preview of theme tokens. Server-renders the current look;
  # website-theme-picker updates the same nodes live when radios change.
  class ThemePreviewSwatchComponent < ApplicationComponent
    # Theme#root_style on the root keeps fonts, radii and the neutral ramp
    # local to this preview; website-theme-picker rewrites it live.
    PREVIEW_BASE = "flex min-h-[14.5rem] flex-col overflow-hidden rounded-xl ring-1 ring-black/10"
    STAGE_BASE = "flex flex-1 flex-col justify-between"
    KICKER_BASE = "text-2xs font-semibold uppercase tracking-[0.16em]"
    HEADLINE_BASE = "text-lg leading-tight"
    BODY_BASE = "text-sm leading-relaxed"
    BUTTON_BASE = "inline-flex w-fit items-center px-3.5 py-1.5 text-xs font-semibold"

    def initialize(theme: nil, site_name: nil)
      tokens = theme.is_a?(Websites::Theme) ? theme.tokens : theme
      @theme = theme.is_a?(Websites::Theme) ? theme : Websites::Theme.new(tokens || {})
      @site_name = site_name
    end

    attr_reader :theme

    def brand_label
      @site_name.to_s.presence || preview_copy(:brand)
    end

    def page_class
      [
        PREVIEW_BASE,
        theme.type_body_class,
        theme.dark? ? "bg-neutral-950 text-white" : "bg-white text-neutral-950"
      ].join(" ")
    end

    def page_style
      theme.root_style
    end

    def stage_class
      [STAGE_BASE, density_pad_class].join(" ")
    end

    def page_chip_class
      [
        "h-6 w-10 shrink-0 rounded-sm border",
        theme.dark? ? "bg-neutral-950 border-white/20" : "bg-white border-neutral-200"
      ].join(" ")
    end

    def button_chip_class
      [BUTTON_BASE, theme.button_shape_class, theme.filled_button_class].join(" ")
    end

    def kicker_chip_class
      [KICKER_BASE, theme.kicker_class].join(" ")
    end

    def headline_class
      [HEADLINE_BASE, theme.type_headline_class].join(" ")
    end

    def body_class
      [BODY_BASE, theme.muted_text_class, theme.type_body_class].join(" ")
    end

    def density_pad_class
      theme.density == "compact" ? "gap-2 p-4 sm:p-5" : "gap-3 p-5 sm:p-6"
    end

    def accent_label
      I18n.t("website.admin.settings.theme.#{theme.accent}")
    end

    def preview_copy(part)
      I18n.t("website.admin.settings.theme.preview.#{part}")
    end
  end
end
