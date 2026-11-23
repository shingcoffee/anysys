# frozen_string_literal: true

module Websites
  module HomeSite
    class IndexComponent < SectionComponent
      CARD_GLYPHS = [
        "M4 4h16v16H4zM4 9h16M9 9v11M4 14h16",
        "M7 3h10v3H7zM6 5H4v16h16V5h-2M8 11h8M8 15h5",
        "M3 4h18v16H3zM3 9h18M7 6.5h.01M10 6.5h.01M7 13h4v4H7zM14 13h3M14 17h3",
        "M12 3l1.8 4.9a2 2 0 0 0 1.2 1.2L20 11l-5 1.9a2 2 0 0 0-1.2 1.2L12 19l-1.8-4.9a2 2 0 0 0-1.2-1.2L4 11l5-1.9a2 2 0 0 0 1.2-1.2z",
        "M15 8a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM5 20v-2a5 5 0 0 1 10 0v2M18 5a3 3 0 0 1 0 6M19 15a4 4 0 0 1 2 3v2",
        "M3 5h18v14H3zM3 6l9 7 9-7"
      ].freeze
      PRINCIPLE_GLYPHS = [
        "M7 3h10v3H7zM6 5H4v16h16V5h-2M8 11h8M8 15h5",
        "M4 4h16v16H4zM8 12l3 3 5-6",
        "M3 3h6v6H3zM15 15h6v6h-6zM9 6h6a3 3 0 0 1 3 3v6M6 9v6a3 3 0 0 0 3 3h6"
      ].freeze

      ASSISTANT_GLYPHS = [
        "M12 3a3 3 0 0 1 3 3v5a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3ZM19 11a7 7 0 0 1-14 0M12 18v3",
        "M4 6c0 1.7 3.6 3 8 3s8-1.3 8-3-3.6-3-8-3-8 1.3-8 3ZM4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3",
        "M7 3h10v3H7zM6 5H4v16h16V5h-2M8 11h8M8 15h5",
        "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18ZM3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9s-1.3 6.3-3.8 9c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3Z",
        "M9 14 4 9l5-5M4 9h10a6 6 0 0 1 0 12h-3",
        "M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6zM9 12l2 2 4-4"
      ].freeze

      def items = list("items").select { |item| present_text?(item["title"]) || present_text?(item["body"]) }
      def process? = variant == :process
      def assistant? = variant == :assistant
      def foundation? = variant == :foundation || page_role == :pricing
      def principles? = variant == :principles

      def grid_class
        return items.size == 4 ? "md:grid-cols-2 lg:grid-cols-4" : "md:grid-cols-3" if process?
        return bento? ? "md:grid-cols-2 lg:grid-cols-4" : "md:grid-cols-2 lg:grid-cols-3" if assistant?

        items.size == 4 ? "md:grid-cols-2" : "md:grid-cols-2 lg:grid-cols-3"
      end

      def section_class
        return "bg-slate-50" if process? || foundation?
        return "bg-gradient-to-b from-white via-violet-50/60 to-white" if assistant?

        "bg-white"
      end

      def card_glyph(index)
        glyphs = if principles? then PRINCIPLE_GLYPHS
        elsif assistant? then ASSISTANT_GLYPHS
        else CARD_GLYPHS
        end
        glyphs[index % glyphs.size]
      end

      # Six cards tile a four-column bento: the first and last span two columns.
      def bento? = items.size == 6
      def wide?(index) = bento? && [0, items.size - 1].include?(index)

      def assistant_card_class(index)
        base = "group relative isolate min-w-0 overflow-hidden rounded-3xl p-7 transition-all duration-300 hover:-translate-y-1 lg:p-8"
        tone = if index.zero?
          "bg-slate-950 text-white shadow-2xl shadow-violet-950/30 ring-1 ring-white/10"
        elsif wide?(index)
          "bg-gradient-to-br from-violet-600 via-fuchsia-600 to-indigo-600 text-white shadow-2xl shadow-fuchsia-500/25"
        else
          "border border-slate-200/80 bg-white shadow-sm hover:border-violet-200 hover:shadow-2xl hover:shadow-violet-500/10"
        end
        "#{base} #{tone} #{'md:col-span-2' if wide?(index)}"
      end

      def assistant_dark?(index) = index.zero? || wide?(index)

      def assistant_tile_class(index)
        return icon_tile_class(index) unless wide?(index) && !index.zero?

        "inline-flex size-12 shrink-0 items-center justify-center rounded-2xl bg-white/15 text-white ring-1 ring-white/30"
      end

      def assistant_title_class(index)
        size = wide?(index) ? "text-[22px] leading-7 lg:text-[26px] lg:leading-8" : "text-[20px] leading-7"
        "relative mt-6 min-w-0 font-bold #{size} #{assistant_dark?(index) ? 'text-white' : 'text-slate-950'} #{tracking_class}"
      end

      def assistant_body_class(index)
        return body_class unless assistant_dark?(index)

        "min-w-0 text-[16px] leading-[26px] text-pretty #{index.zero? ? 'text-slate-300' : 'text-violet-50'}"
      end

      def number(index) = (index + 1).to_s.rjust(2, "0")
    end
  end
end
