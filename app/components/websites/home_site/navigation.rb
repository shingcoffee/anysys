# frozen_string_literal: true

module Websites
  module HomeSite
    # Shared styling for the scoped header (dark glass) and the light mobile sheet.
    module Navigation
      def inner_measure_class = SectionComponent::CONTAINER
      def bar_height_class = "h-16 lg:h-[72px]"
      def signup_label = I18n.t("website.home_site.actions.start")
      def signup_href = href_for(HomeSite::SIGNUP)
      def signup_class = "inline-flex min-h-11 min-w-0 items-center justify-center rounded-full bg-gradient-to-r from-violet-600 via-fuchsia-600 to-indigo-600 px-5 py-2 text-[14px] leading-6 font-semibold text-white shadow-lg shadow-violet-600/30 transition-all duration-300 hover:-translate-y-0.5 hover:shadow-fuchsia-500/40 #{SectionComponent::FOCUS}"

      def nav_pages
        @pages.select do |page|
          next false unless page.is_a?(WebsitePage)
          same_site = website.id ? page.website_id == website.id : page.website.equal?(website)
          same_site && page.customer_id == customer_id && page.published? && page.nav_visible?
        end
      end

      def nav_link_class(page)
        "inline-flex min-h-9 min-w-0 items-center rounded-full px-4 text-[14px] font-medium transition-colors #{nav_link_tone(page)} #{SectionComponent::FOCUS} focus-visible:ring-offset-slate-950"
      end

      def sheet_link_class(page)
        "flex min-h-11 min-w-0 items-center rounded-xl px-4 py-3 text-[16px] leading-6 font-medium #{sheet_link_tone(page)} #{SectionComponent::FOCUS}"
      end

      def nav_link_tone(page)
        current?(page) ? "bg-white/15 text-white shadow-sm" : "text-slate-300 hover:bg-white/10 hover:text-white"
      end

      def sheet_link_tone(page)
        current?(page) ? "bg-violet-50 text-violet-800" : "text-slate-600 hover:bg-slate-50 hover:text-slate-950"
      end

      def nav_button_class
        "inline-flex size-11 shrink-0 items-center justify-center rounded-full text-slate-300 hover:bg-white/10 hover:text-white #{SectionComponent::FOCUS} focus-visible:ring-offset-slate-950"
      end

      def sheet_close_class
        "inline-flex size-11 shrink-0 items-center justify-center rounded-lg text-slate-600 hover:bg-slate-50 hover:text-slate-950 #{SectionComponent::FOCUS}"
      end
    end
  end
end
