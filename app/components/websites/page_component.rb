# frozen_string_literal: true

module Websites
  # Maps a page's JSON sections onto kit ViewComponents. Unknown types are skipped.
  class PageComponent < PublicComponent
    SECTION_TONE = { "dark" => "text-white", "light" => "text-neutral-950" }.freeze

    def initialize(page: nil, theme:, sections: nil, customer_id: nil, website: nil, nav_pages: [], presentation: nil)
      @page = page
      @theme = theme
      @sections_override = sections
      @customer_id = customer_id || page.try(:customer_id)
      validated = HomeSite::Presentation.for(website: website, page: page)
      # An explicit context is only a hint; supplied records remain authoritative.
      @presentation = if validated && presentation.instance_of?(HomeSite::Presentation) && presentation.role == validated.role
        presentation
      else
        validated
      end
      @nav_pages = validated ? validated.nav_pages(nav_pages) : []
    end

    attr_reader :page, :presentation

    def main_attributes
      return { class: "flex-1 min-h-[50vh]" } unless presentation

      { id: "site-main", tabindex: -1, class: "min-w-0 flex-1 bg-white font-sans text-[16px] text-slate-950 antialiased" }
    end

    def section_component(section)
      options = { props: section[:props], theme: section_theme(section), customer_id: customer_id }
      if section[:specialized]
        options.merge!(variant: presentation.variant_for(section[:type], id: section[:id]), page_role: presentation.role, nav_pages: @nav_pages)
      end
      section[:class].new(**options)
    end

    # The platform marketing presentation owns its own bands, so surface
    # overrides only apply to kit sections.
    def section_wrapper(section)
      anchor = section[:id].to_s
      surface = section[:specialized] ? "default" : Websites::SectionKit.style_value(section[:props], "surface")
      custom = custom_appearance(section)
      tone = custom ? SECTION_TONE.fetch(custom) : section_theme(section).surface_class(surface)
      classes = [("scroll-mt-4" if anchor.present?), tone.presence].compact
      attributes = {}
      attributes[:class] = classes.join(" ") if classes.any?
      css = section_styler(section)&.section_css
      attributes[:style] = css if css
      attributes[:data] = { site_section: anchor } if anchor.present?
      attributes[:data] = (attributes[:data] || {}).merge(section_surface: surface) unless surface == "default"
      attributes
    end

    def section_theme(section)
      return theme if section[:specialized]

      base = theme.for_surface(Websites::SectionKit.style_value(section[:props], "surface"))
      custom = custom_appearance(section)
      custom ? base.with_appearance(custom) : base
    end

    def kit_sections
      raw_sections.filter_map do |section|
        hash = normalize_section(section)
        next unless hash

        type = hash["type"].to_s
        next unless Websites::SectionKit.known?(type)

        specialized = presentation&.component_class(type)
        klass = specialized || Websites::SectionKit.component_class(type)
        next unless klass

        { id: hash["id"].to_s, type: type, class: klass, props: stringify(hash["props"]), specialized: specialized.present? }
      end
    end

    private

    # A custom section background re-themes the section light or dark by
    # luminance so the theme's text colors stay readable on it.
    def custom_appearance(section)
      return if section[:specialized]

      Websites::StyleResolver.section_appearance(section[:props][Websites::SectionStyles::PROP])
    end

    def section_styler(section)
      return if section[:specialized]

      Websites::StyleResolver.new(section[:props][Websites::SectionStyles::PROP], theme: theme, type: section[:type])
    end

    def raw_sections
      return Array(@sections_override) unless @sections_override.nil?
      return [] unless page

      Array(page.try(:sections))
    end

    def normalize_section(section)
      return stringify(section) if section.respond_to?(:stringify_keys)
      return { "type" => section.type.to_s, "props" => section.props } if section.respond_to?(:type)

      nil
    end
  end
end
