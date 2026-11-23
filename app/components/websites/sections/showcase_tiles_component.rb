# frozen_string_literal: true

module Websites
  module Sections
    # Product tiles in the Apple / Tesla homepage register: full-bleed and
    # half-width photo tiles, each with a centred title, one line of copy and
    # two pill links. Every tile carries its own light or dark tone, so a
    # stack can alternate regardless of the site appearance.
    class ShowcaseTilesComponent < Websites::SectionComponent
      PILL = "inline-flex h-11 items-center justify-center rounded-full px-6 text-site-base font-medium transition-colors duration-200"

      def tiles
        list("tiles")
      end

      def dark?(tile)
        tile["tone"].to_s == "dark"
      end

      def full?(tile)
        tile["size"].to_s != "half"
      end

      def tile_appearance(tile)
        dark?(tile) ? "dark" : "light"
      end

      def tile_class(tile)
        size = full?(tile) ? "md:col-span-2 min-h-[34rem] sm:min-h-[40rem] lg:min-h-[46rem]" : "min-h-[30rem] sm:min-h-[36rem] lg:min-h-[40rem]"
        surface = dark?(tile) ? "bg-neutral-950 text-white" : "bg-neutral-100 text-neutral-950"
        "group relative isolate flex flex-col overflow-hidden rounded-[1.75rem] #{size} #{surface}"
      end

      def scrim_class(tile)
        dark?(tile) ? "from-black/80 via-black/45 via-40% to-transparent" : "from-white/95 via-white/70 via-40% to-transparent"
      end

      def title_class(tile)
        size = full?(tile) ? "text-site-4xl sm:text-site-5xl lg:text-site-7xl" : "text-site-3xl sm:text-site-4xl lg:text-site-5xl"
        "text-balance break-words leading-[1.02] #{size} #{headline_font_class}"
      end

      def copy_class(tile)
        tone = dark?(tile) ? "text-white/85" : "text-neutral-800"
        "max-w-xl text-pretty text-site-md md:text-site-xl #{tone}"
      end

      def tile_kicker_class(tile)
        "text-site-xs font-semibold uppercase tracking-[0.18em] #{tone_theme(tile).kicker_class}"
      end

      def pills(tile)
        [
          pill(tile, "primary", "#{PILL} #{tone_theme(tile).filled_button_class}"),
          pill(tile, "secondary", "#{PILL} #{secondary_pill_tone(tile)}")
        ].compact
      end

      private

      def tone_theme(tile)
        Websites::Theme.new(theme.tokens.merge("appearance" => tile_appearance(tile)))
      end

      def secondary_pill_tone(tile)
        if dark?(tile)
          "bg-white/10 text-white ring-1 ring-inset ring-white/30 backdrop-blur-md hover:bg-white/20"
        else
          "bg-white/60 text-neutral-950 ring-1 ring-inset ring-neutral-950/15 backdrop-blur-md hover:bg-white"
        end
      end

      def pill(tile, key, css_class)
        label = tile["#{key}_label"].to_s
        return unless present_text?(label)

        { label: label, href: item_href(tile, "#{key}_href"), css_class: css_class }
      end
    end
  end
end
