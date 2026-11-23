# frozen_string_literal: true

module Websites
  class SectionComponent < PublicComponent
    def initialize(props: {}, theme:, customer_id: nil)
      @props = stringify(props)
      @theme = theme
      @customer_id = customer_id
    end

    attr_reader :props

    def prop(*keys)
      keys.each do |key|
        value = props[key.to_s]
        return value.to_s if present_text?(value)
      end
      ""
    end

    def list(key)
      Array(props[key.to_s]).map { |item| stringify(item) }
    end

    def resolved_href(key)
      href_for(props[key.to_s])
    end

    def item_href(item, key = "href")
      href_for(item[key.to_s])
    end

    SPACING_OVERRIDES = {
      "tight" => "py-10 md:py-14",
      "roomy" => "py-28 md:py-44"
    }.freeze

    def style(key)
      Websites::SectionKit.style_value(props, key)
    end

    # Vertical rhythm for the section: the editor's spacing override when set,
    # otherwise the section's own default (theme density for most types).
    def spacing_class(default_class)
      SPACING_OVERRIDES.fetch(style("spacing"), default_class)
    end

    def padding_class
      spacing_class(theme.section_padding_class)
    end

    def header_align(fallback = :left)
      case style("align")
      when "center" then :center
      when "start" then :left
      else fallback
      end
    end

    def gap_class
      theme.stack_gap_class
    end

    def kicker_class
      "text-site-xs font-semibold uppercase tracking-[0.16em] #{theme.kicker_class}"
    end

    def section_heading_class
      "text-balance break-words text-site-3xl sm:text-site-4xl md:text-site-5xl #{headline_font_class}"
    end

    def card_title_class
      "break-words text-site-lg leading-snug md:text-site-xl #{headline_font_class}"
    end

    def subhead_class
      "text-pretty text-site-md md:text-site-lg #{muted_class}"
    end

    def body_class
      "text-pretty text-site-md"
    end

    def header(kicker: nil, heading: nil, subhead: nil, align: :left, css_class: nil, targets: {})
      render Websites::SectionHeaderComponent.new(
        kicker: kicker, heading: heading, subhead: subhead, align: header_align(align), theme: theme, css_class: css_class,
        styler: styler, targets: targets
      )
    end

    def section_type
      self.class.name.demodulize.delete_suffix("Component").underscore
    end

    def styler
      @styler ||= Websites::StyleResolver.new(props[Websites::SectionStyles::PROP], theme: theme, type: section_type)
    end

    # Sections that paint their own band skip it under a custom background.
    def custom_background?
      styler.value("section", "background").present?
    end

    # Marks a restylable text element (top-level "headline" or list-item
    # "items.title") for the Design panel and applies its overrides.
    def el_attrs(target, **html)
      styled_attributes(target, styler.element_css(target), **html)
    end

    # Marks one item of a restylable list; `framed` items already carry
    # card padding, so a background override does not add a frame.
    def item_attrs(array, framed: false, **html)
      extra = styler.item_class(array, framed: framed)
      html[:class] = [html[:class], extra].compact_blank.join(" ") if extra
      styled_attributes(array, styler.item_css(array), **html)
    end

    def render_media(url, alt: "", css_class: "", appearance: nil, eager: false)
      appearance ||= theme.appearance
      src = url.to_s.strip
      if Websites::ImageFit.fitted?(src)
        render Websites::FittedPhotoComponent.new(src: src, alt: alt, css_class: css_class, eager: eager)
      elsif Websites::Href.media?(src)
        if Websites::IllustrationComponent.known?(src)
          render Websites::IllustrationComponent.new(src: src, alt: alt, css_class: css_class, eager: eager)
        else
          tag.img src: src, alt: alt, class: css_class, loading: eager ? "eager" : "lazy", decoding: "async"
        end
      else
        render Websites::PlaceholderImageComponent.new(appearance: appearance, theme: theme, class: css_class)
      end
    end

    def buttons(primary_key: "primary", secondary_key: "secondary", align: :start, secondary_class: nil)
      render Websites::SectionButtonsComponent.new(
        section: self, primary_key: primary_key, secondary_key: secondary_key, align: align, secondary_class: secondary_class
      )
    end

    private

    def styled_attributes(target, css, **html)
      html[:data] = (html[:data] || {}).merge(site_el: target)
      html[:style] = [html[:style], css].compact_blank.join(" ") if css
      tag.attributes(**html)
    end
  end
end
