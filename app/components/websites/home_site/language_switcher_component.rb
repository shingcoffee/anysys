# frozen_string_literal: true

module Websites
  module HomeSite
    # Reuse native locale links/template; restyle the trigger for the dark header.
    class LanguageSwitcherComponent < Websites::LanguageSwitcherComponent
      def trigger_class
        "inline-flex min-h-11 min-w-11 items-center justify-center gap-1.5 rounded-full px-3 text-[14px] font-semibold text-slate-300 hover:bg-white/10 hover:text-white #{SectionComponent::FOCUS} focus-visible:ring-offset-slate-950"
      end

      def option_class(locale)
        tone = current?(locale) ? "bg-violet-50 text-violet-800" : "text-slate-600 hover:bg-slate-50 hover:text-slate-950"
        "flex min-h-11 min-w-0 items-center justify-between gap-3 px-4 py-2 text-[14px] #{tone} #{SectionComponent::FOCUS}"
      end

      def panel_class
        "absolute right-0 max-[280px]:-right-12 top-[calc(100%+0.5rem)] z-50 hidden w-[min(11rem,calc(100vw-2.5rem))] rounded-xl bg-white py-1 text-slate-950 shadow-xl ring-1 ring-slate-200 group-open:block"
      end

      def panel_heading_class = "text-[12px] text-slate-500"
      def check_class = "text-violet-700"
    end
  end
end
