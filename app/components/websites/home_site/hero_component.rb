# frozen_string_literal: true

module Websites
  module HomeSite
    class HeroComponent < SectionComponent
      def lead? = variant == :lead
      def pricing? = variant == :pricing
      def about? = variant == :about || page_role == :about
      def contact? = variant == :contact || page_role == :contact
      def centered? = lead? || pricing? || !split?
      def split? = (about? || contact?) && media_visible?
      def headline_lines = prop("headline").split(/\r?\n/)
      def accent_line?(index) = headline_lines.many? && index == headline_lines.size - 1

      # Joined with a bare newline so the heading's text content equals the saved headline.
      def headline_markup
        spans = headline_lines.each_with_index.map do |line, index|
          tag.span(line, class: ["block", ("#{GRADIENT_TEXT_DARK} pb-[0.08em]" if accent_line?(index))])
        end
        safe_join(spans, "\n")
      end

      def hero_padding_class
        return "pt-16 pb-12 sm:pt-24 lg:pt-28 lg:pb-16" if lead?
        return "pt-16 pb-40 sm:pt-24 lg:pt-28 lg:pb-52" if pricing?

        "pt-16 pb-16 sm:pt-20 lg:pt-24 lg:pb-24"
      end

      def hero_heading_class
        scale = if lead?
          "text-[40px] min-[380px]:text-[46px] sm:text-[64px] lg:text-[84px] lg:leading-[1]"
        elsif split?
          "text-[36px] min-[380px]:text-[42px] sm:text-[52px] lg:text-[56px]"
        else
          "text-[36px] min-[380px]:text-[42px] sm:text-[54px] lg:text-[66px]"
        end
        tracking = zh? ? "tracking-normal" : "tracking-[-0.045em]"
        "min-w-0 w-full max-w-full leading-[1.05] font-bold text-balance text-white #{scale} #{tracking}"
      end

      def hero_subhead_class
        measure = centered? ? "mx-auto max-w-3xl" : "max-w-xl"
        "w-full min-w-0 text-[18px] leading-8 text-slate-300 text-pretty lg:text-[20px] #{measure}"
      end

      def layout_class
        return "grid min-w-0 grid-cols-1 items-center gap-12 lg:grid-cols-12 lg:gap-16" if split?

        "min-w-0"
      end

      def copy_class
        alignment = centered? ? "mx-auto items-center text-center" : "items-start text-left"
        columns = "lg:col-span-6" if split?
        "relative z-10 flex min-w-0 w-full flex-col gap-6 #{alignment} #{columns}"
      end

      def fade(delay) = "animate-fade-up motion-reduce:animate-none [animation-delay:#{delay}ms]"
      def hero_badge = I18n.t("website.home_site.hero_badge")
      def trust_items = lead? ? Array(I18n.t("website.home_site.trust")) : []
      def chips = Array(I18n.t("website.home_site.hero_chips.#{contact? ? 'contact' : 'about'}"))

      def media_visible? = prop("media_mode") != "none" && valid_media?(prop("image_url"))
      def actions? = present_text?(prop("primary_label")) || present_text?(prop("secondary_label"))
    end
  end
end
