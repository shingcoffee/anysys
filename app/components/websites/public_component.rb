# frozen_string_literal: true

require "addressable/uri"

module Websites
  # Shared presentation helpers for the public marketing site. Appearance is a
  # stored token — never `dark:` media queries. Public CTAs use Theme accent
  # classes, not admin `btn-primary`.
  class PublicComponent < ApplicationComponent
    INNER_MEASURE = "max-w-7xl mx-auto min-w-0 px-5 sm:px-8 lg:px-12"
    BUTTON_BASE = "inline-flex h-12 w-full sm:w-auto items-center justify-center gap-2 px-7 text-site-base font-medium transition-colors duration-200"

    attr_reader :theme, :customer_id

    def inner_measure_class
      INNER_MEASURE
    end

    def muted_class
      theme.muted_text_class
    end

    def body_text_class
      theme.body_text_class
    end

    def headline_font_class
      theme.type_headline_class
    end

    def hairline_class
      theme.dark? ? "border-white/[0.08]" : "border-neutral-900/[0.08]"
    end

    def divide_class
      theme.dark? ? "divide-y divide-white/[0.08]" : "divide-y divide-neutral-900/[0.08]"
    end

    def card_border_class
      if theme.dark?
        "bg-white/[0.03] ring-1 ring-inset ring-white/[0.08]"
      else
        "bg-white ring-1 ring-inset ring-neutral-900/[0.07] shadow-sm shadow-neutral-900/[0.03]"
      end
    end

    def image_frame_class
      "overflow-hidden rounded-2xl md:rounded-3xl #{theme.image_frame_class}"
    end

    # BUTTON_BASE plus the theme's corner shape.
    def button_base_class
      "#{BUTTON_BASE} #{theme.button_shape_class}"
    end

    def primary_button_class
      "#{button_base_class} #{theme.filled_button_class}"
    end

    def secondary_button_class
      "#{button_base_class} #{theme.outline_button_class}"
    end

    def cinematic_primary_button_class
      "#{button_base_class} #{theme.cinematic_filled_button_class}"
    end

    def text_link_class
      "inline-flex items-center gap-1.5 text-site-base font-medium underline-offset-4 hover:underline #{theme.kicker_class}"
    end

    def link_hover_class
      theme.link_hover_class
    end

    def cta_band_class
      theme.cta_band_class
    end

    def cta_band_button_class
      if theme.accent == "ink" && theme.dark?
        "#{button_base_class} bg-neutral-950 text-white hover:bg-neutral-800"
      else
        "#{button_base_class} bg-white text-neutral-950 hover:bg-neutral-100"
      end
    end

    def href_for(value)
      href = Websites::Href.resolve(value, customer_id: customer_id, host: helpers.request.host)
      return href unless href&.start_with?("/")

      href = helpers.page_shortcuts_mounted_path(href)

      explicit_locale = helpers.params[:locale].to_s
      return href if I18n.locale == I18n.default_locale && !I18n.available_locales.map(&:to_s).include?(explicit_locale)

      uri = Addressable::URI.parse(href)
      # Keep fragments and repeated query values; replace rather than duplicate
      # locale when a saved URL (or navigation caller) already supplies it.
      query = (uri.query_values(Array) || []).reject { |key, _| key == "locale" }
      uri.query_values = query + [["locale", I18n.locale.to_s]]
      uri.to_s
    end

    def stringify(value)
      return {} if value.blank?
      return value.stringify_keys if value.respond_to?(:stringify_keys)

      {}
    end

    def present_text?(value)
      value.to_s.strip.present?
    end

    def blank_image?(value)
      value.to_s.strip.blank?
    end
  end
end
