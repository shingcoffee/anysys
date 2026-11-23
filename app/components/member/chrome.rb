# frozen_string_literal: true

module Member
  # Presentation for /:cid/member/*. Classes come from the customer's public
  # website theme so the portal matches /:cid/site.
  class Chrome < Websites::PublicComponent
    def initialize(theme)
      @theme = theme
      @customer_id = nil
    end

    def card_class(density = :default)
      padding =
        case density.to_sym
        when :flush   then "p-0 overflow-hidden"
        when :compact then "p-5"
        else "p-6 md:p-8"
        end
      "rounded-2xl md:rounded-3xl #{card_border_class} #{padding}"
    end

    def bar_height_class
      "h-16 md:h-[4.5rem]"
    end

    def nav_link_class(current:)
      "inline-flex max-w-xs shrink-0 items-center overflow-hidden rounded-full px-3.5 py-2 text-site-sm font-medium transition-colors #{nav_tone(current)}"
    end

    def sheet_link_class(current:)
      "flex min-w-0 items-center rounded-full px-4 py-3 text-site-lg font-medium transition-colors #{nav_tone(current)}"
    end

    def nav_button_class
      tone = theme.dark? ? "hover:bg-white/10 text-white/80 hover:text-white focus-visible:ring-white/40" : "hover:bg-neutral-900/[0.04] text-neutral-600 hover:text-neutral-950 focus-visible:ring-neutral-900/20"
      "inline-flex shrink-0 items-center gap-2 rounded-full p-2 text-site-base font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 #{tone}"
    end

    def sheet_panel_class
      theme.dark? ? "bg-neutral-950 text-white" : "bg-white text-neutral-950"
    end

    def focus_ring_class
      theme.dark? ? "focus-visible:ring-white/40" : "focus-visible:ring-neutral-900/20"
    end

    def kicker_pill_class
      ring = theme.dark? ? "ring-white/10 bg-white/[0.04] text-neutral-200" : "ring-neutral-900/10 bg-white text-neutral-700"
      "inline-flex items-center gap-2 rounded-full px-3 py-1 text-site-xs font-medium ring-1 ring-inset #{ring}"
    end

    def well_shape_class
      "inline-flex size-10 shrink-0 items-center justify-center rounded-2xl"
    end

    def icon_well_class
      "#{well_shape_class} #{theme.accent_soft_class}"
    end

    def avatar_class
      "inline-flex items-center justify-center rounded-full font-medium #{theme.accent_soft_class}"
    end

    def form_label_class(required: false)
      base = "mb-1.5 block text-site-sm font-medium"
      required ? "#{base} form-label-required" : base
    end

    def input_class
      if theme.dark?
        "w-full rounded-xl bg-white/[0.04] px-4 py-3 text-site-base text-white ring-1 ring-inset ring-white/15 outline-none transition placeholder:text-neutral-500 focus:ring-2 focus:ring-white/30"
      else
        "w-full rounded-xl bg-white px-4 py-3 text-site-base text-neutral-950 ring-1 ring-inset ring-neutral-900/10 outline-none transition placeholder:text-neutral-400 focus:ring-2 focus:ring-neutral-900/20"
      end
    end

    def code_class
      surface = theme.dark? ? "bg-white/[0.04] ring-white/15" : "bg-neutral-50 ring-neutral-900/10"
      "inline-flex items-center rounded-xl px-3 py-2 font-mono text-site-sm tracking-[0.08em] ring-1 ring-inset select-all #{surface}"
    end

    def menu_panel_class
      if theme.dark?
        "bg-neutral-950 text-white shadow-2xl shadow-black/30 ring-white/10"
      else
        "bg-white text-neutral-950 shadow-xl shadow-neutral-900/[0.08] ring-neutral-900/10"
      end
    end

    def menu_item_class
      if theme.dark?
        "block px-4 py-2.5 text-site-sm text-white/80 transition-colors hover:bg-white/[0.06] hover:text-white"
      else
        "block px-4 py-2.5 text-site-sm text-neutral-600 transition-colors hover:bg-neutral-50 hover:text-neutral-950"
      end
    end

    def menu_danger_class
      if theme.dark?
        "block px-4 py-2.5 text-site-sm text-rose-300 transition-colors hover:bg-rose-400/10"
      else
        "block px-4 py-2.5 text-site-sm text-rose-700 transition-colors hover:bg-rose-50"
      end
    end

    def block_button_class(kind = :primary)
      source = kind == :secondary ? secondary_button_class : primary_button_class
      source.sub("w-full sm:w-auto", "w-full")
    end

    def danger_link_class
      "inline-flex items-center text-site-sm font-medium #{theme.dark? ? "text-rose-300 hover:text-rose-200" : "text-rose-700 hover:text-rose-800"}"
    end

    def error_text_class
      "text-site-xs #{theme.dark? ? "text-rose-300" : "text-rose-700"}"
    end

    def danger_quiet_class
      if theme.dark?
        "inline-flex h-12 items-center justify-center rounded-full px-5 text-site-sm font-medium text-rose-300 hover:bg-rose-400/10"
      else
        "inline-flex h-12 items-center justify-center rounded-full px-5 text-site-sm font-medium text-rose-700 hover:bg-rose-50"
      end
    end

    def notice_class
      "rounded-2xl px-4 py-3 text-site-sm ring-1 ring-inset #{theme.accent_soft_class} #{theme.dark? ? "ring-white/10" : "ring-current/10"}"
    end

    def alert_class
      if theme.dark?
        "rounded-2xl bg-rose-400/10 px-4 py-3 text-site-sm text-rose-200 ring-1 ring-inset ring-rose-400/20"
      else
        "rounded-2xl bg-rose-50 px-4 py-3 text-site-sm text-rose-800 ring-1 ring-inset ring-rose-200"
      end
    end

    def pager_link_class
      hover = theme.dark? ? "hover:bg-white/10" : "hover:bg-neutral-900/[0.04]"
      "inline-flex h-10 items-center gap-1 rounded-full px-4 text-site-sm font-medium transition-colors #{theme.kicker_class} #{hover}"
    end

    def table_header_class
      "px-5 py-3 text-site-xs font-semibold uppercase tracking-[0.08em] #{muted_class}"
    end

    def table_divide_class
      theme.dark? ? "divide-y divide-white/[0.08]" : "divide-y divide-neutral-900/[0.08]"
    end

    def table_row_class
      hover = theme.dark? ? "hover:bg-white/[0.03]" : "hover:bg-neutral-50"
      "transition-colors #{hover}"
    end

    def list_row_class
      "flex items-center justify-between gap-4 py-4"
    end

    def label_class
      "text-site-xs font-semibold uppercase tracking-[0.08em] #{muted_class}"
    end

    def title_class
      "text-balance text-site-4xl leading-[1.06] sm:text-site-5xl #{headline_font_class}"
    end

    def section_title_class
      "text-site-2xl leading-tight #{headline_font_class}"
    end

    def subhead_class
      "max-w-2xl text-site-lg #{body_text_class}"
    end

    def body_copy_class
      "text-site-base #{body_text_class}"
    end

    def success_well_class
      theme.dark? ? "bg-emerald-400/10 text-emerald-200" : "bg-emerald-50 text-emerald-800"
    end

    def warning_well_class
      theme.dark? ? "bg-amber-400/10 text-amber-200" : "bg-amber-50 text-amber-800"
    end

    def value_tone_class(tone)
      case tone
      when :success then theme.dark? ? "text-emerald-300" : "text-emerald-700"
      when :warning then theme.dark? ? "text-amber-300" : "text-amber-700"
      else ""
      end
    end

    private

    def nav_tone(current)
      if current
        theme.dark? ? "bg-white/10 text-white" : "bg-neutral-900/[0.04] text-neutral-950"
      else
        hover = theme.dark? ? "hover:bg-white/5 hover:text-white" : "hover:bg-neutral-900/[0.03] hover:text-neutral-950"
        "#{muted_class} #{hover}"
      end
    end
  end
end
