# frozen_string_literal: true

module Websites
  # Turns a section's validated `styles` prop into inline CSS declarations
  # for the public renderer. Only tokens SectionStyles accepts reach the
  # output, so stored values can never inject arbitrary CSS. Theme-aware
  # tokens resolve against the section's own theme and recolor with it.
  class StyleResolver
    # Base values of the --text-site-* scale in app/assets/tailwind/application.css.
    TEXT_SITE_SCALE = {
      "xs" => "0.75rem", "sm" => "0.875rem", "base" => "1rem", "md" => "1.0625rem", "lg" => "1.1875rem",
      "xl" => "1.375rem", "2xl" => "1.625rem", "3xl" => "2rem", "4xl" => "2.5rem", "5xl" => "3.25rem",
      "6xl" => "4rem", "7xl" => "5rem", "8xl" => "6rem"
    }.freeze
    SHAPE_RADII = { "pill" => "9999px", "rounded" => "0.625rem", "square" => "0" }.freeze
    ALIGN_CSS = {
      "start" => "text-align: start; margin-inline-start: 0; margin-inline-end: auto;",
      "center" => "text-align: center; margin-inline: auto;",
      "end" => "text-align: end; margin-inline-start: auto; margin-inline-end: 0;"
    }.freeze
    BACKGROUND_ROLES = { "band" => "band", "accent_soft" => "accent_soft", "accent" => "accent_fill", "ink" => "ink", "canvas" => "canvas" }.freeze
    # Text inside a recolored item follows the item color, not theme classes.
    ITEM_TEXT_INHERIT = "[&_:is(p,h2,h3,h4,dd,dt,blockquote,li,figcaption,time)]:[color:inherit]"
    # Items that are not already padded cards gain a frame once filled.
    ITEM_FRAME = "rounded-2xl p-5 md:p-6"
    LIGHT_ON_DARK = "#fff"
    DARK_ON_LIGHT = "#0a0a0a"

    # "dark" / "light" when a custom section background needs the section to
    # re-theme for contrast; nil keeps the surface theme.
    def self.section_appearance(styles)
      hex = new(styles, theme: nil, type: nil).value("section", "background")
      return unless hex

      dark_hex?(hex) ? "dark" : "light"
    end

    def self.dark_hex?(hex)
      channels = hex.delete_prefix("#").scan(/../).map do |pair|
        c = pair.to_i(16) / 255.0
        c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
      end
      luminance = (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])
      (1.05 / (luminance + 0.05)) > ((luminance + 0.05) / 0.05)
    end

    def initialize(styles, theme:, type:)
      @styles = styles.respond_to?(:to_h) ? styles.to_h.deep_stringify_keys : {}
      @theme = theme
      @kinds = type ? SectionStyles.target_kinds(type) : {}
    end

    # A stored value only when it passes validation for the target's kind.
    def value(target, attribute)
      raw = @styles.dig(target.to_s, attribute.to_s)
      kind = kind_for(target)
      return if raw.blank? || kind.nil?

      raw.to_s if SectionStyles.valid_value?(kind, attribute, raw)
    end

    def section_css
      css = []
      background = value("section", "background")
      css << "background-color: #{background};" if background
      heading = value("section", "heading_font")
      css << "--font-site-heading: #{Fonts.stack(heading)};" if heading
      body = value("section", "body_font")
      css.push("--font-site-body: #{Fonts.stack(body)};", "--font-sans: #{Fonts.stack(body)};") if body
      css << scale_css(value("section", "scale"))
      join(css)
    end

    def element_css(target)
      css = []
      color = value(target, "color")
      css << "color: #{color_css(color)};" if color
      font = value(target, "font")
      css << "font-family: #{Fonts.stack(font)};" if font
      css << scale_css(value(target, "size"))
      weight = value(target, "weight")
      css << "font-weight: #{SectionStyles::WEIGHTS.fetch(weight)};" if weight
      italic = value(target, "italic")
      css << "font-style: #{italic};" if italic
      align = value(target, "align")
      css << ALIGN_CSS.fetch(align) if align
      join(css)
    end

    def item_css(array)
      css = []
      background = value(array, "background")
      css << "background-color: #{background_css(background)};" if background
      text = item_text_color(array, background)
      css << "color: #{text};" if text
      join(css)
    end

    def item_class(array, framed: false)
      background = value(array, "background")
      classes = []
      classes << ITEM_TEXT_INHERIT if item_text_color(array, background)
      classes << ITEM_FRAME if background && !framed
      classes.join(" ").presence
    end

    # Primary buttons take fill + text; both buttons take the shape.
    def button_css(role)
      css = []
      shape = value("buttons", "shape")
      css << "border-radius: #{SHAPE_RADII.fetch(shape)};" if shape
      if role.to_s == "primary"
        fill = value("buttons", "fill")
        css << "background-color: #{color_css(fill)};" if fill
        text = value("buttons", "text")
        text_css = text ? color_css(text) : (fill && on_color(fill))
        css << "color: #{text_css};" if text_css
      end
      join(css)
    end

    private

    def kind_for(target)
      key = target.to_s
      return :section if key == "section"

      @kinds[key]
    end

    def scale_css(scale)
      return unless scale

      factor = SectionStyles::SCALES.fetch(scale)
      TEXT_SITE_SCALE.map { |step, base| "--text-site-#{step}: calc(#{base} * #{factor});" }.join(" ")
    end

    def color_css(token)
      return token if SectionStyles.hex?(token)

      @theme ? @theme.color(token) : nil
    end

    def background_css(token)
      return token if SectionStyles.hex?(token)

      @theme&.color(BACKGROUND_ROLES.fetch(token))
    end

    def item_text_color(array, background)
      text = value(array, "text")
      return color_css(text) if text
      return unless background

      on_background(background)
    end

    # Readable text over a filled background.
    def on_background(token)
      return (self.class.dark_hex?(token) ? LIGHT_ON_DARK : DARK_ON_LIGHT) if SectionStyles.hex?(token)

      case token
      when "accent" then @theme&.color("accent_on_fill")
      when "ink" then @theme&.color("inverse")
      end
    end

    def on_color(token)
      return (self.class.dark_hex?(token) ? LIGHT_ON_DARK : DARK_ON_LIGHT) if SectionStyles.hex?(token)

      case token
      when "accent" then @theme&.color("accent_on_fill")
      when "ink" then @theme&.color("inverse")
      when "inverse" then @theme&.color("ink")
      end
    end

    def join(css)
      css.compact.join(" ").presence
    end
  end
end
