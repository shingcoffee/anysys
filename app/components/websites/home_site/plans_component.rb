# frozen_string_literal: true

module Websites
  module HomeSite
    class PlansComponent < SectionComponent
      FEATURED_FRAME = "rounded-3xl bg-gradient-to-br from-violet-500 via-fuchsia-500 to-sky-400 p-0.5 shadow-2xl shadow-fuchsia-500/25 lg:-translate-y-4 lg:hover:-translate-y-5"
      FEATURED_SURFACE = "rounded-[calc(1.5rem-2px)] bg-gradient-to-br from-[#120a2e] via-[#1e1048] to-[#0f0a24] text-white"

      def tiers = list("tiers").select { |tier| tier.values_at("name", "price").any? { |value| present_text?(value) } }
      def featured?(tier) = tier["highlight"].to_s == "featured"
      def features(tier) = tier["features"].to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)
      def featured_label = prop("featured_label").presence || I18n.t("website.public.pricing.featured")
      def overlap? = page_role == :pricing

      def section_class
        overlap? ? "relative z-10 -mt-32 pb-16 lg:-mt-40 lg:pb-24" : "bg-white #{padding_class}"
      end

      def tier_frame_class(tier)
        "relative min-w-0 transition-transform duration-300 hover:-translate-y-1 #{FEATURED_FRAME if featured?(tier)}"
      end

      def tier_class(tier)
        tone = featured?(tier) ? FEATURED_SURFACE : "rounded-3xl border border-slate-200/80 bg-white shadow-xl shadow-slate-900/5"
        "relative flex h-full min-w-0 flex-col gap-5 p-6 xl:p-7 #{tone}"
      end

      def tier_heading_class(tier) = featured?(tier) ? "text-white" : "text-slate-950"
      def tier_body_class(tier) = featured?(tier) ? "text-violet-100/90" : "text-slate-600"
      def feature_border_class(tier) = featured?(tier) ? "border-white/15" : "border-slate-200"
      def feature_icon_class(tier) = featured?(tier) ? "bg-gradient-to-br from-violet-400 to-fuchsia-500 text-white" : "bg-violet-100 text-violet-700"
      def featured_badge_class = "absolute -top-3.5 left-1/2 inline-flex -translate-x-1/2 items-center gap-1.5 whitespace-nowrap rounded-full bg-gradient-to-r from-violet-500 via-fuchsia-500 to-sky-500 px-3.5 py-1 text-[12px] leading-5 font-bold text-white shadow-lg shadow-fuchsia-500/40"

      def tier_button_class(tier)
        return primary_button_class.sub("sm:w-auto", "") if featured?(tier)

        "inline-flex min-h-12 min-w-0 w-full items-center justify-center rounded-full bg-slate-900 px-4 py-3 text-[15px] leading-6 font-semibold text-white transition-all duration-300 hover:bg-violet-700 hover:-translate-y-0.5 #{FOCUS}"
      end
    end
  end
end
