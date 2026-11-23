# frozen_string_literal: true

module Websites
  # Compact language dropdown for public marketing navigation. It uses GET links
  # rather than the admin locale form, so anonymous language selection preserves
  # the exact page and query without JavaScript.
  class LanguageSwitcherComponent < ApplicationComponent
    SHORT_NAMES = { en: "EN", "zh-CN": "中文" }.freeze

    def initialize(theme:, current: I18n.locale)
      @theme = theme
      @current = current.to_sym
    end

    def locales
      LocaleSwitcherComponent::DISPLAY_NAMES.keys
    end

    def display_name(locale)
      LocaleSwitcherComponent::DISPLAY_NAMES.fetch(locale)
    end

    def short_name(locale)
      SHORT_NAMES.fetch(locale)
    end

    def current_short_name
      short_name(@current)
    end

    def current?(locale)
      locale == @current
    end

    def locale_href(locale)
      query = request.query_parameters.merge("locale" => locale.to_s)
      "#{request.path}?#{query.to_query}"
    end

    def trigger_class
      base = "inline-flex h-9 min-w-[4rem] items-center justify-center gap-1.5 rounded-full px-3 text-site-xs font-semibold transition-colors"
      tone = if @theme.dark?
        "text-white/80 hover:bg-white/10 hover:text-white"
      else
        "text-neutral-600 hover:bg-neutral-900/[0.04] hover:text-neutral-950"
      end
      "#{base} #{tone} focus-visible:outline-none focus-visible:ring-2 #{focus_ring_class}"
    end

    def panel_class
      tone = if @theme.dark?
        "bg-neutral-950 ring-white/10 text-white shadow-2xl shadow-black/30"
      else
        "bg-white ring-neutral-900/10 text-neutral-950 shadow-xl shadow-neutral-900/[0.08]"
      end
      "absolute right-0 top-[calc(100%+0.5rem)] z-50 w-44 overflow-hidden rounded-2xl py-1 ring-1 group-open:block hidden #{tone}"
    end

    def panel_heading_class
      @theme.dark? ? "text-white/50" : "text-neutral-500"
    end

    def option_class(locale)
      active = if @theme.dark?
        current?(locale) ? "bg-white/10 text-white" : "text-white/75 hover:bg-white/[0.06] hover:text-white"
      else
        current?(locale) ? "bg-violet-50 text-violet-800" : "text-neutral-600 hover:bg-neutral-50 hover:text-neutral-950"
      end
      "flex min-h-10 items-center justify-between gap-3 px-4 py-2 text-site-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset #{focus_ring_class} #{active}"
    end

    def check_class
      @theme.dark? ? "text-white" : "text-violet-700"
    end

    def chevron_class
      "size-3.5 transition-transform group-open:rotate-180"
    end

    private

    def focus_ring_class
      @theme.dark? ? "focus-visible:ring-white/60" : "focus-visible:ring-violet-600/40"
    end
  end
end
