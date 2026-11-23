# frozen_string_literal: true

module FormFields
  class PageComponent < ApplicationComponent
    include ThemeResolver

    def initialize(page:, show_title: false, show_description: false, css_class: nil, theme: {})
      @page = page
      @show_title = show_title
      @show_description = show_description
      @css_class = css_class
      @theme = theme
    end

    private

    attr_reader :page, :show_title, :show_description, :css_class, :theme

    def wrapper_classes
      [
        resolve_form_width(theme),
        "mx-auto",
        resolve_form_padding(theme),
        resolve_form_shadow(theme),
        resolve_form_border(theme),
        resolve_form_bg(theme),
        resolve_font_class(theme),
        resolve_container_radius_class(theme),
        css_class
      ].compact.reject(&:blank?).join(" ")
    end

    def title
      page.name
    end

    def description
      page.description
    end

    def settings
      page.configuration_json&.dig("settings") || {}
    end
  end
end
