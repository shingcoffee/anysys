# frozen_string_literal: true

module Websites
  # Font families the public site may load from fonts.bunny.net. Theme font
  # pairings and builder style overrides reference these keys; the stylesheet
  # only requests the families a page actually uses.
  module Fonts
    SANS_FALLBACK = "ui-sans-serif, system-ui, sans-serif"
    SERIF_FALLBACK = "Georgia, ui-serif, serif"
    MONO_FALLBACK = "ui-monospace, SFMono-Regular, Menlo, monospace"

    FAMILIES = {
      "inter" => { name: "Inter", fallback: SANS_FALLBACK, slug: "inter:400,500,600,700" },
      "newsreader" => { name: "Newsreader", fallback: SERIF_FALLBACK, slug: "newsreader:400,400i,500,600" },
      "fraunces" => { name: "Fraunces", fallback: SERIF_FALLBACK, slug: "fraunces:400,400i,500,600,700" },
      "playfair" => { name: "Playfair Display", fallback: SERIF_FALLBACK, slug: "playfair-display:400,400i,500,600,700" },
      "source_sans" => { name: "Source Sans 3", fallback: SANS_FALLBACK, slug: "source-sans-3:400,400i,500,600,700" },
      "space_grotesk" => { name: "Space Grotesk", fallback: SANS_FALLBACK, slug: "space-grotesk:400,500,600,700" },
      "dm_sans" => { name: "DM Sans", fallback: SANS_FALLBACK, slug: "dm-sans:400,400i,500,600,700" },
      "outfit" => { name: "Outfit", fallback: SANS_FALLBACK, slug: "outfit:400,500,600,700" },
      "cormorant" => { name: "Cormorant Garamond", fallback: SERIF_FALLBACK, slug: "cormorant-garamond:400,400i,500,600,700" },
      "jost" => { name: "Jost", fallback: SANS_FALLBACK, slug: "jost:400,400i,500,600,700" },
      "instrument_serif" => { name: "Instrument Serif", fallback: SERIF_FALLBACK, slug: "instrument-serif:400,400i" },
      "instrument_sans" => { name: "Instrument Sans", fallback: SANS_FALLBACK, slug: "instrument-sans:400,500,600,700" },
      "plex_sans" => { name: "IBM Plex Sans", fallback: SANS_FALLBACK, slug: "ibm-plex-sans:400,400i,500,600,700" },
      "plex_mono" => { name: "IBM Plex Mono", fallback: MONO_FALLBACK, slug: "ibm-plex-mono:400,500,600" },
      "bricolage" => { name: "Bricolage Grotesque", fallback: SANS_FALLBACK, slug: "bricolage-grotesque:400,500,600,700,800" }
    }.freeze

    STYLESHEET_HOST = "https://fonts.bunny.net/css?family="

    module_function

    def keys
      FAMILIES.keys
    end

    def known?(key)
      FAMILIES.key?(key.to_s)
    end

    def label(key)
      I18n.t("website.fonts.#{key}")
    end

    def stack(key)
      family = FAMILIES.fetch(key.to_s)
      "'#{family.fetch(:name)}', #{family.fetch(:fallback)}"
    end

    # nil when no known family is requested.
    def stylesheet_url(keys)
      slugs = Array(keys).map(&:to_s).uniq.select { |key| known?(key) }.map { |key| FAMILIES.fetch(key).fetch(:slug) }
      return if slugs.empty?

      "#{STYLESHEET_HOST}#{slugs.join('|')}"
    end
  end
end
