# frozen_string_literal: true

module Websites
  module HomeSite
    class CtaComponent < SectionComponent
      ROUTE_GLYPHS = {
        "platform" => "M3 3h7v7H3zM14 14h7v7h-7zM14 6h4v4M6 14v4h4",
        "pricing" => "M20.6 13.4 13.4 20.6a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.8ZM7.5 7.5h.01",
        "workspace" => "M12 3l1.8 4.9a2 2 0 0 0 1.2 1.2L20 11l-5 1.9a2 2 0 0 0-1.2 1.2L12 19l-1.8-4.9a2 2 0 0 0-1.2-1.2L4 11l5-1.9a2 2 0 0 0 1.2-1.2z"
      }.freeze

      def padding_class = contact? ? "pt-6 pb-16 lg:pt-8 lg:pb-24" : "py-16 lg:py-24"
      def contact? = variant == :contact_next_steps
      def render? = present_text?(prop("headline")) || present_text?(prop("body")) || (contact? ? contact_routes.any? : present_text?(prop("button_label")))
      def trust_items = Array(I18n.t("website.home_site.trust"))

      def next_step_pages
        return [] unless contact?

        nav_pages.select do |page|
          page.is_a?(WebsitePage) && page.customer_id == customer_id && page.published? && page.nav_visible? && %w[platform pricing].include?(page.slug) && present_text?(page.title)
        end
      end

      def contact_routes
        routes = next_step_pages.filter_map do |page|
          href = href_for(page.slug)
          { label: page.title, href: href, description: I18n.t("website.home_site.contact.routes.#{page.slug}"), kind: page.slug, workspace: false } if href
        end
        href = resolved_href("button_href")
        if present_text?(prop("button_label")) && href
          routes << { label: prop("button_label"), href: href, description: I18n.t("website.home_site.contact.routes.workspace"), kind: "workspace", workspace: true }
        end
        routes
      end

      def route_grid_class(count)
        return "md:grid-cols-2 lg:grid-cols-3" if count >= 3
        "md:grid-cols-2" if count == 2
      end

      def route_class(route)
        tone = route[:workspace] ? "border-transparent bg-slate-950 text-white shadow-2xl shadow-violet-900/30" : "border-slate-200/80 bg-white shadow-sm hover:border-violet-200 hover:shadow-2xl hover:shadow-violet-500/10"
        "group/button relative isolate flex min-h-11 min-w-0 flex-col overflow-hidden rounded-3xl border p-7 transition-all duration-300 hover:-translate-y-1 lg:p-8 #{tone} #{FOCUS}"
      end

      def route_index(route) = ROUTE_GLYPHS.keys.index(route[:kind]) || 0

      def closing_button_class
        "#{BUTTON} shrink-0 bg-white text-slate-950 shadow-xl shadow-black/20 hover:bg-violet-50 hover:-translate-y-0.5 focus-visible:ring-offset-slate-950 #{FOCUS}"
      end
    end
  end
end
