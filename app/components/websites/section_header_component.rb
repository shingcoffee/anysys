# frozen_string_literal: true

module Websites
  # Kicker / heading / subhead block shared by every kit section so the
  # typographic rhythm stays identical across the site.
  class SectionHeaderComponent < PublicComponent
    TARGETS = { kicker: "kicker", heading: "heading", subhead: "subhead" }.freeze

    # `targets` maps a slot to the prop key it renders when a section feeds
    # the header from differently named props (e.g. heading: "headline").
    def initialize(theme:, kicker: nil, heading: nil, subhead: nil, align: :left, css_class: nil, styler: nil, targets: {})
      @theme = theme
      @kicker = kicker.to_s
      @heading = heading.to_s
      @subhead = subhead.to_s
      @align = align.to_sym
      @css_class = css_class
      @styler = styler
      @targets = TARGETS.merge(targets.to_h.symbolize_keys)
    end

    attr_reader :kicker, :heading, :subhead

    def render?
      [kicker, heading, subhead].any? { |value| present_text?(value) }
    end

    def centered?
      @align == :center
    end

    def wrapper_class
      base = centered? ? "mx-auto max-w-3xl items-center text-center" : "max-w-3xl items-start"
      ["flex flex-col gap-4 md:gap-5", base, @css_class].compact.join(" ")
    end

    def kicker_class
      "text-site-xs font-semibold uppercase tracking-[0.16em] #{theme.kicker_class}"
    end

    def heading_class
      "text-balance break-words text-site-3xl sm:text-site-4xl md:text-site-5xl #{headline_font_class}"
    end

    def subhead_class
      "max-w-2xl text-pretty text-site-md md:text-site-lg #{muted_class}"
    end

    def slot_attrs(slot, css_class)
      target = @targets.fetch(slot)
      css = @styler&.element_css(target)
      tag.attributes(class: css_class, style: css, data: { site_el: target })
    end
  end
end
