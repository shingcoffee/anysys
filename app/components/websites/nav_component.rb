# frozen_string_literal: true

module Websites
  # Sticky public nav: site name, published pages, locale switcher, mobile sheet.
  class NavComponent < PublicComponent
    def initialize(website:, pages: [], current_slug: nil, embed: false, theme: nil)
      @website = website
      @pages = Array(pages)
      @current_slug = current_slug.to_s
      @embed = embed
      @theme = theme || Websites::Theme.new(website.try(:theme))
      @customer_id = website.try(:customer_id)
    end

    attr_reader :website, :embed

    def nav_pages
      home, rest = @pages.partition { |page| home_page?(page) }
      home + rest
    end

    def home_href
      path = PageShortcuts::PublicPath.website_home(customer_id: customer_id, host: helpers.request.host)
      "#{helpers.page_shortcuts_mounted_path(path)}?#{ { locale: I18n.locale }.to_query }"
    end

    def page_href(page)
      slug = page_slug(page)
      return home_href if slug.blank? || home_page?(page)

      href = href_for(slug)
      return home_href unless href

      # Page slugs resolve to local site routes; carry the explicit language
      # through navigation because a GET locale switch does not set a cookie.
      uri = Addressable::URI.parse(href)
      uri.query_values = (uri.query_values || {}).merge("locale" => I18n.locale.to_s)
      uri.to_s
    end

    def page_title(page)
      if page.respond_to?(:title)
        page.title.to_s
      else
        stringify(page)["title"].to_s
      end
    end

    def page_slug(page)
      if page.respond_to?(:slug)
        page.slug.to_s
      else
        stringify(page)["slug"].to_s
      end
    end

    def home_page?(page)
      flag = page[:home] if page.respond_to?(:[])
      flag = page.home if flag.nil? && page.respond_to?(:home)
      return flag unless flag.nil?

      page_slug(page).blank?
    end

    def current?(page)
      page_slug(page) == @current_slug
    end

    def nav_link_class(page)
      "whitespace-nowrap rounded-full px-3.5 py-2 text-site-sm font-medium transition-colors #{nav_link_tone(page)}"
    end

    def sheet_link_class(page)
      "flex min-w-0 items-center rounded-full px-4 py-3 text-site-lg font-medium transition-colors #{nav_link_tone(page)}"
    end

    def nav_link_tone(page)
      if current?(page)
        theme.dark? ? "bg-white/10 text-white" : "bg-neutral-900/[0.04] text-neutral-950"
      else
        hover = theme.dark? ? "hover:bg-white/5 hover:text-white" : "hover:bg-neutral-900/[0.03] hover:text-neutral-950"
        "#{muted_class} #{hover}"
      end
    end

    def nav_button_class
      tone = theme.dark? ? "hover:bg-white/10 text-white/80 hover:text-white focus-visible:ring-white/40" : "hover:bg-neutral-900/[0.04] text-neutral-600 hover:text-neutral-950 focus-visible:ring-neutral-900/20"
      "inline-flex shrink-0 items-center gap-2 rounded-full p-2 text-site-base font-medium transition-colors " \
        "focus-visible:outline-none focus-visible:ring-2 #{tone}"
    end

    def bar_height_class
      "h-16 md:h-[4.5rem]"
    end

    def site_name
      website.try(:name).to_s
    end

    def tagline
      website.try(:tagline).to_s
    end

    def open_label
      I18n.t("website.public.nav.open")
    end

    def close_label
      I18n.t("website.public.nav.close")
    end

    def sheet_panel_class
      theme.dark? ? "bg-neutral-950 text-white" : "bg-white text-neutral-950"
    end

    def sheet_title_id
      "website-nav-title"
    end
  end
end
