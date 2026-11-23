# frozen_string_literal: true

module Websites
  module Sections
    # Slim centered launch pill — Vercel / Linear “Introducing X →”.
    class AnnouncementComponent < Websites::SectionComponent
      def show?
        present_text?(prop("badge")) || present_text?(prop("body")) || present_text?(prop("link_label"))
      end

      def href
        resolved_href("href")
      end

      def pill_class
        if theme.dark?
          "bg-white/[0.04] ring-1 ring-inset ring-white/10 text-neutral-200"
        else
          "bg-white ring-1 ring-inset ring-neutral-900/10 text-neutral-800 shadow-sm shadow-neutral-900/[0.04]"
        end
      end

      def badge_class
        "inline-flex items-center rounded-full px-2 py-0.5 text-site-xs font-semibold tracking-wide #{theme.accent_soft_class}"
      end

      def link_class
        "inline-flex items-center gap-1 text-site-sm font-medium #{theme.kicker_class}"
      end

      def aria_label
        return if present_text?(prop("body")) || present_text?(prop("link_label"))
        return unless href.present?

        I18n.t("website.public.announcement.learn_more")
      end
    end
  end
end
