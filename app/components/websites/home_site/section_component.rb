# frozen_string_literal: true

module Websites
  module HomeSite
    class SectionComponent < Websites::SectionComponent
      CONTAINER = "mx-auto w-full max-w-[1280px] min-w-0 px-5 sm:px-8 lg:px-10 [overflow-wrap:anywhere]"
      FOCUS = "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500 focus-visible:ring-offset-2"
      BUTTON = "group/button inline-flex min-h-12 min-w-0 w-full items-center justify-center gap-2 rounded-full px-6 py-3 text-[16px] font-semibold leading-6 transition-all duration-300 sm:w-auto"
      BADGE = "inline-flex min-w-0 w-fit max-w-full items-center gap-1.5 rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-0.5 text-[12px] leading-5 font-semibold text-emerald-700"
      GRADIENT_TEXT = "bg-gradient-to-r from-violet-600 via-fuchsia-500 to-indigo-600 bg-clip-text text-transparent"
      GRADIENT_TEXT_DARK = "bg-gradient-to-r from-violet-300 via-fuchsia-300 to-sky-300 bg-clip-text text-transparent"
      # Icon tiles cycle through these so adjacent cards never share a hue.
      ICON_TILES = [
        "from-violet-500 to-indigo-600 shadow-violet-500/30",
        "from-fuchsia-500 to-pink-500 shadow-fuchsia-500/30",
        "from-sky-400 to-blue-600 shadow-sky-500/30",
        "from-amber-400 to-orange-500 shadow-orange-500/30",
        "from-emerald-400 to-teal-600 shadow-emerald-500/30",
        "from-indigo-500 to-purple-600 shadow-indigo-500/30"
      ].freeze
      GRID_PATTERN = "bg-[linear-gradient(to_right,rgba(255,255,255,0.06)_1px,transparent_1px),linear-gradient(to_bottom,rgba(255,255,255,0.06)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_70%_60%_at_50%_0%,#000_60%,transparent_100%)]"

      def initialize(props: {}, theme:, customer_id: nil, variant: nil, page_role: nil, nav_pages: [])
        super(props: props, theme: theme, customer_id: customer_id)
        @variant = variant
        @page_role = page_role
        @nav_pages = Array(nav_pages)
      end

      attr_reader :variant, :page_role, :nav_pages

      def inner_measure_class = CONTAINER
      def padding_class = "py-16 lg:py-24"
      def zh? = I18n.locale.to_s == "zh-CN"
      def tracking_class = zh? ? "tracking-normal" : "tracking-[-0.03em]"
      def kicker_class(tone: :light)
        tone_class = tone == :dark ? "border-white/15 bg-white/5 text-violet-200" : "border-violet-200/80 bg-violet-50 text-violet-700"
        "inline-flex min-w-0 w-fit max-w-full items-center gap-2 rounded-full border px-3.5 py-1 text-[13px] leading-5 font-semibold #{tone_class}"
      end

      def section_heading_class(tone: :light)
        color = tone == :dark ? "text-white" : "text-slate-950"
        "min-w-0 max-w-full text-[30px] leading-[1.1] font-bold text-balance sm:text-[40px] lg:text-[52px] #{color} #{tracking_class}"
      end

      def compact_heading_class = "min-w-0 max-w-full text-[28px] leading-tight font-bold text-slate-950 text-balance lg:text-[40px] #{tracking_class}"
      def body_class = "min-w-0 text-[16px] leading-[26px] text-slate-600 text-pretty"
      def subhead_class(tone: :light) = "min-w-0 text-[18px] leading-8 text-pretty lg:text-[20px] #{tone == :dark ? 'text-slate-300' : 'text-slate-600'}"
      def primary_button_class = "#{BUTTON} bg-gradient-to-r from-violet-600 via-fuchsia-600 to-indigo-600 bg-[length:200%_100%] bg-left text-white shadow-lg shadow-violet-600/30 hover:bg-right hover:shadow-xl hover:shadow-fuchsia-500/40 hover:-translate-y-0.5 #{FOCUS}"
      def secondary_button_class = "#{BUTTON} border border-slate-300 bg-white text-slate-900 shadow-sm hover:border-violet-300 hover:bg-violet-50 hover:-translate-y-0.5 #{FOCUS}"
      def ghost_button_class = "#{BUTTON} border border-white/20 bg-white/5 text-white backdrop-blur hover:bg-white/10 hover:border-white/40 hover:-translate-y-0.5 #{FOCUS} focus-visible:ring-offset-slate-950"
      def media_frame_class = "relative aspect-[4/3] w-full overflow-hidden rounded-3xl"
      def icon_tile_class(index, size: "size-12")
        "inline-flex #{size} shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br text-white shadow-lg #{ICON_TILES[index % ICON_TILES.size]}"
      end

      def valid_media?(url)
        src = url.to_s.strip
        return Websites::IllustrationComponent.known?(src) if Websites::Href::BUNDLED_ILLUSTRATION_PATH.match?(src)
        return Rails.public_path.join(src.delete_prefix("/")).file? if Websites::Href::BUNDLED_PHOTO_PATH.match?(src)

        Websites::Href.media?(src)
      end

      def paragraphs(value)
        value.to_s.split(/\r?\n\s*\r?\n/).reject(&:blank?)
      end

      # Invalid destinations remain readable copy, never a disabled button.
      def action(label, destination, css_class: primary_button_class, arrow: false)
        return unless present_text?(label)

        href = href_for(destination)
        return tag.span(label, class: "min-w-0 text-[16px] leading-[26px]") unless href

        link_to(href, class: css_class) do
          safe_join([tag.span(label, class: "min-w-0"), (arrow_icon if arrow)].compact)
        end
      end

      def arrow_icon
        tag.svg(viewBox: "0 0 20 20", fill: "none", stroke: "currentColor", "stroke-width": "2", "aria-hidden": "true", focusable: "false",
                class: "size-4 shrink-0 transition-transform duration-300 group-hover/button:translate-x-1") do
          tag.path(d: "M4 10h12m-5-5 5 5-5 5", "stroke-linecap": "round", "stroke-linejoin": "round")
        end
      end

      def sparkle_icon(css_class: "size-3.5")
        tag.svg(viewBox: "0 0 20 20", fill: "currentColor", "aria-hidden": "true", focusable: "false", class: "shrink-0 #{css_class}") do
          tag.path(d: "M10 1.5l1.9 5.1a2 2 0 0 0 1.2 1.2l5.1 1.9-5.1 1.9a2 2 0 0 0-1.2 1.2L10 18.5l-1.9-5.7a2 2 0 0 0-1.2-1.2L1.8 9.7l5.1-1.9a2 2 0 0 0 1.2-1.2z")
        end
      end

      def check_icon(css_class: "size-4")
        tag.svg(viewBox: "0 0 20 20", fill: "none", stroke: "currentColor", "stroke-width": "2.2", "aria-hidden": "true", focusable: "false", class: "shrink-0 #{css_class}") do
          tag.path(d: "m5 10.5 3.2 3L15 6.5", "stroke-linecap": "round", "stroke-linejoin": "round")
        end
      end

      def glyph(path, css_class: "size-6")
        tag.svg(viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": "1.7", "stroke-linecap": "round", "stroke-linejoin": "round",
                "aria-hidden": "true", focusable: "false", class: css_class) { tag.path(d: path) }
      end

      # Blurred colour fields + fine grid behind dark surfaces.
      def aurora(intensity: :full)
        blobs = [
          "-left-40 -top-40 size-[34rem] bg-violet-600/40",
          "right-[-10rem] top-10 size-[30rem] bg-fuchsia-500/25 [animation-delay:-6s]",
          "bottom-[-14rem] left-1/3 size-[36rem] bg-indigo-500/30 [animation-delay:-12s]"
        ]
        blobs << "right-1/4 top-1/3 size-[18rem] bg-sky-400/15 [animation-delay:-3s]" if intensity == :full
        tag.div("aria-hidden": "true", class: "pointer-events-none absolute inset-0 -z-10 overflow-hidden") do
          safe_join([
            *blobs.map { |blob| tag.span(class: "absolute rounded-full blur-[110px] animate-aurora motion-reduce:animate-none #{blob}") },
            tag.span(class: "absolute inset-0 #{GRID_PATTERN}"),
            tag.span(class: "absolute inset-x-0 bottom-0 h-px bg-gradient-to-r from-transparent via-white/20 to-transparent")
          ])
        end
      end

      def section_intro(heading_class: section_heading_class, align: :left, tone: :light)
        centered = align == :center
        tag.div(class: "flex min-w-0 w-full flex-col gap-4 #{centered ? 'mx-auto max-w-4xl items-center text-center' : 'items-start'}") do
          safe_join([
            (tag.p(class: kicker_class(tone: tone)) { safe_join([sparkle_icon, tag.span(prop("kicker"))]) } if present_text?(prop("kicker"))),
            (tag.h2(prop("heading"), class: heading_class) if present_text?(prop("heading"))),
            (tag.p(prop("subhead"), class: "w-full #{'max-w-2xl' if centered} #{subhead_class(tone: tone)}") if present_text?(prop("subhead")))
          ].compact)
        end
      end
    end
  end
end
