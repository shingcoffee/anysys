# frozen_string_literal: true

# Document chrome for layouts/website.html.erb — title, meta description, and
# theme classes. Controllers pass @website/@page/@theme/@preview/@edit_url/@embed.
module WebsitesHelper
  def websites_layout_theme
    @theme || Websites::Theme.new(websites_layout_site&.try(:theme))
  end

  # Only the families the theme pairs plus any a section style override picks.
  def websites_font_stylesheet(theme = websites_layout_theme, sections: websites_layout_sections)
    Websites::Fonts.stylesheet_url(theme.font_keys + Websites::SectionStyles.font_keys(sections))
  end

  def websites_embed?
    @embed == true || params[:embed].to_s == "1"
  end

  def websites_document_title
    page_title = websites_layout_page&.try(:title).to_s.presence
    seo_title = websites_layout_seo["title"].to_s.presence
    site_name = websites_layout_site&.try(:name).to_s.presence
    [page_title, seo_title || site_name].compact.join(" · ").presence || site_name || page_title
  end

  def websites_meta_description
    websites_layout_seo["description"].to_s.presence || websites_first_section_headline
  end

  private

  def websites_layout_site
    @website || @site
  end

  def websites_layout_page
    @page
  end

  # Catalog previews render sections that do not belong to a saved page.
  def websites_layout_sections
    Array(@preview_sections || websites_layout_page&.try(:sections))
  end

  def websites_layout_seo
    raw = websites_layout_site&.try(:seo)
    raw.respond_to?(:stringify_keys) ? raw.stringify_keys : {}
  end

  def websites_first_section_headline
    Array(websites_layout_page&.try(:sections)).each do |section|
      hash = section.respond_to?(:stringify_keys) ? section.stringify_keys : nil
      props = hash ? hash["props"] : section.try(:props)
      props = props.respond_to?(:stringify_keys) ? props.stringify_keys : {}
      text = %w[headline heading quote].filter_map { |key| props[key].to_s.presence }.first
      return text if text.present?
    end
    nil
  end
end
