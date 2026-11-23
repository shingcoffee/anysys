# frozen_string_literal: true

module Websites
  # Maps a website's stored theme tokens to Tailwind classes and root CSS
  # variables for the public marketing layout. Appearance is a stored token —
  # do not use `dark:` media queries. Do not reuse ThemeResolver (form-card
  # presets). Named themes live in ThemePresets; catalog pairing in ThemePairing.
  class Theme
    APPEARANCES = %w[light dark].freeze
    ACCENTS     = %w[azure ink gold forest rose violet copper indigo teal crimson plum olive].freeze
    DENSITIES   = %w[spacious compact].freeze
    CORNERS     = %w[sharp soft round].freeze
    NEUTRALS    = %w[neutral warm cool].freeze

    # Font pairing per `type` token: heading/body/accent family keys from
    # Websites::Fonts, plus the headline weight + tracking that suits them.
    PAIRINGS = {
      "sans" => { heading: "inter", body: "inter", accent: "fraunces", headline: "font-semibold tracking-[-0.03em]" },
      "serif" => { heading: "newsreader", body: "newsreader", accent: "newsreader", headline: "font-normal tracking-[-0.015em]" },
      "display" => { heading: "fraunces", body: "inter", accent: "fraunces", headline: "font-medium tracking-[-0.035em]" },
      "grotesk" => { heading: "inter", body: "inter", accent: "fraunces", headline: "font-bold tracking-[-0.045em]" },
      "classic" => { heading: "playfair", body: "source_sans", accent: "playfair", headline: "font-medium tracking-[-0.02em]" },
      "modern" => { heading: "space_grotesk", body: "inter", accent: "space_grotesk", headline: "font-medium tracking-[-0.04em]" },
      "geometric" => { heading: "outfit", body: "dm_sans", accent: "outfit", headline: "font-semibold tracking-[-0.03em]" },
      "elegant" => { heading: "cormorant", body: "jost", accent: "cormorant", headline: "font-medium tracking-[-0.01em]" },
      "gallery" => { heading: "instrument_serif", body: "instrument_sans", accent: "instrument_serif", headline: "font-normal tracking-[-0.02em]" },
      "technical" => { heading: "plex_sans", body: "plex_sans", accent: "plex_mono", headline: "font-semibold tracking-[-0.025em]" },
      "expressive" => { heading: "bricolage", body: "dm_sans", accent: "bricolage", headline: "font-bold tracking-[-0.04em]" }
    }.freeze
    TYPES = PAIRINGS.keys.freeze

    OPTIONS = {
      "appearance" => APPEARANCES,
      "accent" => ACCENTS,
      "type" => TYPES,
      "density" => DENSITIES,
      "corners" => CORNERS,
      "neutral" => NEUTRALS
    }.freeze
    TOKENS = OPTIONS.keys.freeze

    DEFAULTS = {
      "appearance" => "light",
      "accent" => "azure",
      "type" => "sans",
      "density" => "spacious",
      "corners" => "soft",
      "neutral" => "neutral"
    }.freeze

    # Tailwind v4 compiles rounded-* to var(--radius-*); "soft" keeps the
    # app defaults from application.css.
    RADII = {
      "sharp" => { "--radius-sm" => "0.125rem", "--radius-md" => "0.1875rem", "--radius-lg" => "0.25rem",
                   "--radius-xl" => "0.25rem", "--radius-2xl" => "0.375rem", "--radius-3xl" => "0.5rem" },
      "soft" => {},
      "round" => { "--radius-sm" => "0.5rem", "--radius-md" => "0.75rem", "--radius-lg" => "1rem",
                   "--radius-xl" => "1.25rem", "--radius-2xl" => "1.75rem", "--radius-3xl" => "2.25rem" }
    }.freeze

    # Tailwind v4.1 stone / slate ramps, re-bound onto the neutral-* variables
    # every public component uses.
    NEUTRAL_RAMPS = {
      "neutral" => {},
      "warm" => {
        "50" => "oklch(98.5% 0.001 106.423)", "100" => "oklch(97% 0.001 106.424)", "200" => "oklch(92.3% 0.003 48.717)",
        "300" => "oklch(86.9% 0.005 56.366)", "400" => "oklch(70.9% 0.01 56.259)", "500" => "oklch(55.3% 0.013 58.071)",
        "600" => "oklch(44.4% 0.011 73.639)", "700" => "oklch(37.4% 0.01 67.558)", "800" => "oklch(26.8% 0.007 34.298)",
        "900" => "oklch(21.6% 0.006 56.043)", "950" => "oklch(14.7% 0.004 49.25)"
      },
      "cool" => {
        "50" => "oklch(98.4% 0.003 247.858)", "100" => "oklch(96.8% 0.007 247.896)", "200" => "oklch(92.9% 0.013 255.508)",
        "300" => "oklch(86.9% 0.022 252.894)", "400" => "oklch(70.4% 0.04 256.788)", "500" => "oklch(55.4% 0.046 257.417)",
        "600" => "oklch(44.6% 0.043 257.281)", "700" => "oklch(37.2% 0.044 257.287)", "800" => "oklch(27.9% 0.041 260.031)",
        "900" => "oklch(20.8% 0.042 265.755)", "950" => "oklch(12.9% 0.042 264.695)"
      }
    }.freeze

    def initialize(tokens = {})
      raw = (tokens || {}).to_h.stringify_keys
      @tokens = DEFAULTS.merge(raw.slice(*TOKENS))
      OPTIONS.each { |token, allowed| @tokens[token] = DEFAULTS[token] unless allowed.include?(@tokens[token].to_s) }
      @preset_key = raw["preset"].to_s if Websites::ThemePresets.known?(raw["preset"])
    end

    def self.preset(key)
      Websites::ThemePresets.theme(key)
    end

    # Skeleton or layout key → its paired named theme, honoring the platform
    # row's theme_key override when the row exists. Card loops pass `records`
    # (key => row, preloaded once) instead of querying per key.
    def self.for_catalog(key, records: nil)
      record = if records
        records[key.to_s]
      else
        WebsiteSkeleton.find_by(key: key.to_s) || WebsiteLayout.find_by(key: key.to_s)
      end
      record ? for_record(record) : preset(Websites::ThemePairing.for_catalog(key))
    end

    # A WebsiteSkeleton / WebsiteLayout row → its paired named theme, honoring
    # the platform owner's theme_key override.
    def self.for_record(record)
      preset(record.theme_preset_key)
    end

    # The theme a page renders with: its own preset override, else the site's.
    def self.for_page(website:, page: nil)
      key = page.try(:theme_key).to_s
      return preset(key) if Websites::ThemePresets.known?(key)

      new(website.try(:theme))
    end

    def self.default_tokens?(raw)
      new(raw).tokens == DEFAULTS
    end

    attr_reader :tokens, :preset_key

    def appearance = tokens["appearance"]
    def accent     = tokens["accent"]
    def type       = tokens["type"]
    def density    = tokens["density"]
    def corners    = tokens["corners"]
    def neutral    = tokens["neutral"]
    def dark?      = appearance == "dark"

    # Tokens as persisted on Website#theme.
    def to_stored
      preset_key ? tokens.merge("preset" => preset_key) : tokens.dup
    end

    # True when the tokens drift from the named theme they started from.
    def customized?
      preset_key.present? && Websites::ThemePresets.tokens(preset_key) != tokens
    end

    def with_appearance(value)
      self.class.new(to_stored.merge("appearance" => value.to_s))
    end

    def pairing
      PAIRINGS.fetch(type)
    end

    def heading_stack = Websites::Fonts.stack(pairing.fetch(:heading))
    def body_stack    = Websites::Fonts.stack(pairing.fetch(:body))
    def accent_stack  = Websites::Fonts.stack(pairing.fetch(:accent))

    def font_keys
      pairing.values_at(:heading, :body, :accent).uniq
    end

    # CSS custom properties for <html>: fonts, radii and the neutral ramp.
    def root_style
      vars = {
        "--font-site-heading" => heading_stack,
        "--font-site-body" => body_stack,
        "--font-family-sans" => body_stack,
        "--font-sans" => body_stack,
        "--font-family-serif" => accent_stack,
        "--font-serif" => accent_stack
      }
      vars.merge!(RADII.fetch(corners))
      NEUTRAL_RAMPS.fetch(neutral).each { |shade, value| vars["--color-neutral-#{shade}"] = value }
      vars.map { |name, value| "#{name}: #{value};" }.join(" ")
    end

    def html_class
      [type_body_class, appearance == "dark" ? "bg-neutral-950" : "bg-white"].join(" ")
    end

    # The theme a section renders with for a given surface override. Only
    # "contrast" flips appearance; the other surfaces keep the site tokens.
    def for_surface(surface)
      return self unless surface.to_s == "contrast"

      with_appearance(dark? ? "light" : "dark")
    end

    # Band behind a section. Evaluated on the theme returned by #for_surface,
    # so "contrast" already sees the flipped appearance.
    def surface_class(surface)
      case surface.to_s
      when "muted" then band_class
      when "contrast" then dark? ? "bg-neutral-950 text-white" : "bg-white text-neutral-950"
      when "accent" then ACCENT_SURFACE.fetch(accent).fetch(dark? ? :dark : :light)
      end
    end

    # CSS color for a semantic role, resolved for this appearance. Used by
    # StyleResolver so theme-aware swatches follow the theme.
    def color(role)
      case role.to_s
      when "accent" then accent_color(:text)
      when "accent_fill" then accent_color(:fill)
      when "accent_on_fill" then accent_color(:on_fill)
      when "accent_soft" then dark? ? soft_mix(ACCENT_COLORS.fetch(accent).fetch(:soft).last) : css_color(ACCENT_COLORS.fetch(accent).fetch(:soft).first)
      when "ink" then dark? ? "#fff" : css_color("neutral-950")
      when "body" then css_color(dark? ? "neutral-300" : "neutral-600")
      when "muted" then css_color(dark? ? "neutral-400" : "neutral-500")
      when "inverse" then dark? ? css_color("neutral-950") : "#fff"
      when "canvas" then dark? ? css_color("neutral-950") : "#fff"
      when "band" then dark? ? "color-mix(in oklab, #fff 2.5%, transparent)" : css_color("neutral-50")
      end
    end

    def body_class
      [
        "min-h-screen flex flex-col",
        appearance == "dark" ? "bg-neutral-950 text-white" : "bg-white text-neutral-950",
        type_body_class,
        "antialiased tracking-normal [&_:is(h1,h2,h3,h4,h5,h6)]:[color:inherit]"
      ].join(" ")
    end

    def nav_class
      if dark?
        "bg-neutral-950/70 backdrop-blur-xl backdrop-saturate-150 border-b border-white/[0.08]"
      else
        "bg-white/70 backdrop-blur-xl backdrop-saturate-150 border-b border-neutral-900/[0.06]"
      end
    end

    def footer_class
      if dark?
        "bg-neutral-950 border-t border-white/[0.08]"
      else
        "bg-neutral-50 border-t border-neutral-900/[0.06]"
      end
    end

    def muted_text_class
      dark? ? "text-neutral-400" : "text-neutral-500"
    end

    def body_text_class
      dark? ? "text-neutral-300" : "text-neutral-600"
    end

    def band_class
      dark? ? "bg-white/[0.025]" : "bg-neutral-50"
    end

    def accent_soft_class
      ACCENT_SOFT.fetch(accent).fetch(dark? ? :dark : :light)
    end

    def accent_ring_class
      ACCENT_RING.fetch(accent).fetch(dark? ? :dark : :light)
    end

    def accent_dot_class
      ACCENT_DOT.fetch(accent)
    end

    def glow_class
      PLACEHOLDER_BLOB.fetch(accent).fetch(dark? ? :dark : :light)
    end

    def outline_button_class
      if dark?
        "bg-white/[0.06] text-white ring-1 ring-inset ring-white/15 hover:bg-white/10"
      else
        "bg-white text-neutral-900 ring-1 ring-inset ring-neutral-900/10 hover:bg-neutral-50 shadow-sm shadow-neutral-900/5"
      end
    end

    def kicker_class
      ACCENT_TEXT.fetch(accent).fetch(dark? ? :dark : :light)
    end

    def filled_button_class
      ACCENT_BUTTON.fetch(accent).fetch(dark? ? :dark : :light)
    end

    def cinematic_filled_button_class
      "bg-white text-neutral-950 hover:bg-neutral-100"
    end

    # Sharp themes square their buttons off; soft and round keep the pill.
    def button_shape_class
      corners == "sharp" ? "rounded-md" : "rounded-full"
    end

    def cta_band_class
      if accent == "ink" && dark?
        "bg-white text-neutral-950"
      else
        CTA_BAND.fetch(accent)
      end
    end

    def link_hover_class
      LINK_HOVER.fetch(accent).fetch(dark? ? :dark : :light)
    end

    def section_padding_class
      density == "compact" ? "py-16 md:py-24" : "py-20 md:py-32"
    end

    def stack_gap_class
      density == "compact" ? "gap-8 md:gap-12" : "gap-10 md:gap-16"
    end

    def placeholder_class
      PLACEHOLDER.fetch(accent).fetch(dark? ? :dark : :light)
    end

    def placeholder_blob_class
      PLACEHOLDER_BLOB.fetch(accent).fetch(dark? ? :dark : :light)
    end

    def image_frame_class
      dark? ? "ring-1 ring-white/10 shadow-2xl shadow-black/50" : "ring-1 ring-neutral-900/[0.06] shadow-xl shadow-neutral-900/[0.06]"
    end

    def type_body_class
      "font-site-body"
    end

    def type_headline_class
      "font-site-heading #{pairing.fetch(:headline)}"
    end

    private

    def accent_color(part)
      shades = ACCENT_COLORS.fetch(accent).fetch(part)
      css_color(dark? ? shades.last : shades.first)
    end

    def css_color(shade)
      shade == "white" ? "#fff" : "var(--color-#{shade})"
    end

    def soft_mix(shade)
      "color-mix(in oklab, #{css_color(shade)} 10%, transparent)"
    end

    # [light, dark] Tailwind shades per accent; each shade is already used by
    # a class map below, so Tailwind emits its --color-* variable.
    ACCENT_COLORS = {
      "azure" => { text: %w[sky-700 sky-300], fill: %w[sky-600 sky-500], on_fill: %w[white white], soft: %w[sky-50 sky-400] },
      "ink" => { text: %w[neutral-950 white], fill: %w[neutral-950 white], on_fill: %w[white neutral-950], soft: %w[neutral-100 white] },
      "gold" => { text: %w[amber-800 amber-300], fill: %w[amber-700 amber-500], on_fill: %w[white neutral-950], soft: %w[amber-50 amber-400] },
      "forest" => { text: %w[emerald-800 emerald-300], fill: %w[emerald-700 emerald-500], on_fill: %w[white neutral-950], soft: %w[emerald-50 emerald-400] },
      "rose" => { text: %w[rose-700 rose-300], fill: %w[rose-600 rose-500], on_fill: %w[white white], soft: %w[rose-50 rose-400] },
      "violet" => { text: %w[violet-700 violet-300], fill: %w[violet-600 violet-500], on_fill: %w[white white], soft: %w[violet-50 violet-400] },
      "copper" => { text: %w[orange-800 orange-300], fill: %w[orange-700 orange-500], on_fill: %w[white neutral-950], soft: %w[orange-50 orange-400] },
      "indigo" => { text: %w[indigo-700 indigo-300], fill: %w[indigo-600 indigo-500], on_fill: %w[white white], soft: %w[indigo-50 indigo-400] },
      "teal" => { text: %w[teal-700 teal-300], fill: %w[teal-700 teal-500], on_fill: %w[white neutral-950], soft: %w[teal-50 teal-400] },
      "crimson" => { text: %w[red-700 red-300], fill: %w[red-700 red-500], on_fill: %w[white white], soft: %w[red-50 red-400] },
      "plum" => { text: %w[fuchsia-800 fuchsia-300], fill: %w[fuchsia-700 fuchsia-500], on_fill: %w[white white], soft: %w[fuchsia-50 fuchsia-400] },
      "olive" => { text: %w[lime-800 lime-300], fill: %w[lime-800 lime-400], on_fill: %w[white neutral-950], soft: %w[lime-50 lime-400] }
    }.freeze

    ACCENT_TEXT = {
      "azure"   => { light: "text-sky-700", dark: "text-sky-300" },
      "ink"     => { light: "text-neutral-950", dark: "text-white" },
      "gold"    => { light: "text-amber-800", dark: "text-amber-300" },
      "forest"  => { light: "text-emerald-800", dark: "text-emerald-300" },
      "rose"    => { light: "text-rose-700", dark: "text-rose-300" },
      "violet"  => { light: "text-violet-700", dark: "text-violet-300" },
      "copper"  => { light: "text-orange-800", dark: "text-orange-300" },
      "indigo"  => { light: "text-indigo-700", dark: "text-indigo-300" },
      "teal"    => { light: "text-teal-700", dark: "text-teal-300" },
      "crimson" => { light: "text-red-700", dark: "text-red-300" },
      "plum"    => { light: "text-fuchsia-800", dark: "text-fuchsia-300" },
      "olive"   => { light: "text-lime-800", dark: "text-lime-300" }
    }.freeze

    ACCENT_BUTTON = {
      "azure"   => { light: "bg-sky-600 hover:bg-sky-500 text-white", dark: "bg-sky-500 hover:bg-sky-400 text-white" },
      "ink"     => { light: "bg-neutral-950 hover:bg-neutral-800 text-white", dark: "bg-white hover:bg-neutral-200 text-neutral-950" },
      "gold"    => { light: "bg-amber-700 hover:bg-amber-600 text-white", dark: "bg-amber-500 hover:bg-amber-400 text-neutral-950" },
      "forest"  => { light: "bg-emerald-700 hover:bg-emerald-600 text-white", dark: "bg-emerald-500 hover:bg-emerald-400 text-neutral-950" },
      "rose"    => { light: "bg-rose-600 hover:bg-rose-500 text-white", dark: "bg-rose-500 hover:bg-rose-400 text-white" },
      "violet"  => { light: "bg-violet-600 hover:bg-violet-500 text-white", dark: "bg-violet-500 hover:bg-violet-400 text-white" },
      "copper"  => { light: "bg-orange-700 hover:bg-orange-600 text-white", dark: "bg-orange-500 hover:bg-orange-400 text-neutral-950" },
      "indigo"  => { light: "bg-indigo-600 hover:bg-indigo-500 text-white", dark: "bg-indigo-500 hover:bg-indigo-400 text-white" },
      "teal"    => { light: "bg-teal-700 hover:bg-teal-600 text-white", dark: "bg-teal-500 hover:bg-teal-400 text-neutral-950" },
      "crimson" => { light: "bg-red-700 hover:bg-red-600 text-white", dark: "bg-red-500 hover:bg-red-400 text-white" },
      "plum"    => { light: "bg-fuchsia-700 hover:bg-fuchsia-600 text-white", dark: "bg-fuchsia-500 hover:bg-fuchsia-400 text-white" },
      "olive"   => { light: "bg-lime-800 hover:bg-lime-700 text-white", dark: "bg-lime-400 hover:bg-lime-300 text-neutral-950" }
    }.freeze

    CTA_BAND = {
      "azure"   => "bg-sky-950 text-white",
      "ink"     => "bg-neutral-950 text-white",
      "gold"    => "bg-stone-900 text-amber-50",
      "forest"  => "bg-emerald-950 text-white",
      "rose"    => "bg-rose-950 text-white",
      "violet"  => "bg-violet-950 text-white",
      "copper"  => "bg-stone-900 text-orange-50",
      "indigo"  => "bg-indigo-950 text-white",
      "teal"    => "bg-teal-950 text-white",
      "crimson" => "bg-red-950 text-white",
      "plum"    => "bg-fuchsia-950 text-white",
      "olive"   => "bg-lime-950 text-lime-50"
    }.freeze

    ACCENT_SOFT = {
      "azure"   => { light: "bg-sky-50 text-sky-800", dark: "bg-sky-400/10 text-sky-200" },
      "ink"     => { light: "bg-neutral-100 text-neutral-900", dark: "bg-white/10 text-white" },
      "gold"    => { light: "bg-amber-50 text-amber-900", dark: "bg-amber-400/10 text-amber-200" },
      "forest"  => { light: "bg-emerald-50 text-emerald-900", dark: "bg-emerald-400/10 text-emerald-200" },
      "rose"    => { light: "bg-rose-50 text-rose-800", dark: "bg-rose-400/10 text-rose-200" },
      "violet"  => { light: "bg-violet-50 text-violet-800", dark: "bg-violet-400/10 text-violet-200" },
      "copper"  => { light: "bg-orange-50 text-orange-900", dark: "bg-orange-400/10 text-orange-200" },
      "indigo"  => { light: "bg-indigo-50 text-indigo-800", dark: "bg-indigo-400/10 text-indigo-200" },
      "teal"    => { light: "bg-teal-50 text-teal-900", dark: "bg-teal-400/10 text-teal-200" },
      "crimson" => { light: "bg-red-50 text-red-800", dark: "bg-red-400/10 text-red-200" },
      "plum"    => { light: "bg-fuchsia-50 text-fuchsia-900", dark: "bg-fuchsia-400/10 text-fuchsia-200" },
      "olive"   => { light: "bg-lime-50 text-lime-900", dark: "bg-lime-400/10 text-lime-200" }
    }.freeze

    ACCENT_RING = {
      "azure"   => { light: "ring-2 ring-sky-600", dark: "ring-2 ring-sky-400" },
      "ink"     => { light: "ring-2 ring-neutral-950", dark: "ring-2 ring-white" },
      "gold"    => { light: "ring-2 ring-amber-700", dark: "ring-2 ring-amber-400" },
      "forest"  => { light: "ring-2 ring-emerald-700", dark: "ring-2 ring-emerald-400" },
      "rose"    => { light: "ring-2 ring-rose-600", dark: "ring-2 ring-rose-400" },
      "violet"  => { light: "ring-2 ring-violet-600", dark: "ring-2 ring-violet-400" },
      "copper"  => { light: "ring-2 ring-orange-700", dark: "ring-2 ring-orange-400" },
      "indigo"  => { light: "ring-2 ring-indigo-600", dark: "ring-2 ring-indigo-400" },
      "teal"    => { light: "ring-2 ring-teal-700", dark: "ring-2 ring-teal-400" },
      "crimson" => { light: "ring-2 ring-red-700", dark: "ring-2 ring-red-400" },
      "plum"    => { light: "ring-2 ring-fuchsia-700", dark: "ring-2 ring-fuchsia-400" },
      "olive"   => { light: "ring-2 ring-lime-800", dark: "ring-2 ring-lime-400" }
    }.freeze

    ACCENT_DOT = {
      "azure"   => "bg-sky-500",
      "ink"     => "bg-neutral-900",
      "gold"    => "bg-amber-600",
      "forest"  => "bg-emerald-600",
      "rose"    => "bg-rose-500",
      "violet"  => "bg-violet-500",
      "copper"  => "bg-orange-600",
      "indigo"  => "bg-indigo-500",
      "teal"    => "bg-teal-600",
      "crimson" => "bg-red-600",
      "plum"    => "bg-fuchsia-600",
      "olive"   => "bg-lime-700"
    }.freeze

    LINK_HOVER = {
      "azure"   => { light: "hover:text-sky-700", dark: "hover:text-sky-300" },
      "ink"     => { light: "hover:text-neutral-950", dark: "hover:text-white" },
      "gold"    => { light: "hover:text-amber-800", dark: "hover:text-amber-300" },
      "forest"  => { light: "hover:text-emerald-800", dark: "hover:text-emerald-300" },
      "rose"    => { light: "hover:text-rose-700", dark: "hover:text-rose-300" },
      "violet"  => { light: "hover:text-violet-700", dark: "hover:text-violet-300" },
      "copper"  => { light: "hover:text-orange-800", dark: "hover:text-orange-300" },
      "indigo"  => { light: "hover:text-indigo-700", dark: "hover:text-indigo-300" },
      "teal"    => { light: "hover:text-teal-700", dark: "hover:text-teal-300" },
      "crimson" => { light: "hover:text-red-700", dark: "hover:text-red-300" },
      "plum"    => { light: "hover:text-fuchsia-800", dark: "hover:text-fuchsia-300" },
      "olive"   => { light: "hover:text-lime-800", dark: "hover:text-lime-300" }
    }.freeze

    PLACEHOLDER = {
      "azure"   => { light: "bg-gradient-to-br from-sky-100 via-indigo-50 to-cyan-100", dark: "bg-gradient-to-br from-slate-950 via-sky-950 to-indigo-950" },
      "ink"     => { light: "bg-gradient-to-br from-neutral-100 via-zinc-50 to-stone-200", dark: "bg-gradient-to-br from-neutral-950 via-neutral-900 to-zinc-950" },
      "gold"    => { light: "bg-gradient-to-br from-amber-50 via-orange-50 to-stone-100", dark: "bg-gradient-to-br from-stone-950 via-amber-950 to-neutral-950" },
      "forest"  => { light: "bg-gradient-to-br from-emerald-50 via-teal-50 to-lime-50", dark: "bg-gradient-to-br from-emerald-950 via-teal-950 to-neutral-950" },
      "rose"    => { light: "bg-gradient-to-br from-rose-50 via-fuchsia-50 to-orange-50", dark: "bg-gradient-to-br from-rose-950 via-neutral-950 to-fuchsia-950" },
      "violet"  => { light: "bg-gradient-to-br from-violet-50 via-indigo-50 to-fuchsia-50", dark: "bg-gradient-to-br from-violet-950 via-indigo-950 to-neutral-950" },
      "copper"  => { light: "bg-gradient-to-br from-orange-50 via-amber-50 to-stone-100", dark: "bg-gradient-to-br from-stone-950 via-orange-950 to-neutral-950" },
      "indigo"  => { light: "bg-gradient-to-br from-indigo-50 via-violet-50 to-sky-50", dark: "bg-gradient-to-br from-indigo-950 via-slate-950 to-neutral-950" },
      "teal"    => { light: "bg-gradient-to-br from-teal-50 via-cyan-50 to-sky-50", dark: "bg-gradient-to-br from-teal-950 via-cyan-950 to-neutral-950" },
      "crimson" => { light: "bg-gradient-to-br from-red-50 via-orange-50 to-rose-50", dark: "bg-gradient-to-br from-red-950 via-neutral-950 to-rose-950" },
      "plum"    => { light: "bg-gradient-to-br from-fuchsia-50 via-pink-50 to-violet-50", dark: "bg-gradient-to-br from-fuchsia-950 via-neutral-950 to-violet-950" },
      "olive"   => { light: "bg-gradient-to-br from-lime-50 via-stone-50 to-amber-50", dark: "bg-gradient-to-br from-lime-950 via-stone-950 to-neutral-950" }
    }.freeze

    PLACEHOLDER_BLOB = {
      "azure"   => { light: "bg-sky-300/50", dark: "bg-sky-500/20" },
      "ink"     => { light: "bg-neutral-400/40", dark: "bg-white/10" },
      "gold"    => { light: "bg-amber-300/50", dark: "bg-amber-400/20" },
      "forest"  => { light: "bg-emerald-300/50", dark: "bg-emerald-400/20" },
      "rose"    => { light: "bg-rose-300/50", dark: "bg-rose-400/20" },
      "violet"  => { light: "bg-violet-300/50", dark: "bg-violet-400/20" },
      "copper"  => { light: "bg-orange-300/50", dark: "bg-orange-400/20" },
      "indigo"  => { light: "bg-indigo-300/50", dark: "bg-indigo-500/20" },
      "teal"    => { light: "bg-teal-300/50", dark: "bg-teal-400/20" },
      "crimson" => { light: "bg-red-300/50", dark: "bg-red-500/20" },
      "plum"    => { light: "bg-fuchsia-300/50", dark: "bg-fuchsia-400/20" },
      "olive"   => { light: "bg-lime-300/50", dark: "bg-lime-400/20" }
    }.freeze

    ACCENT_SURFACE = {
      "azure"   => { light: "bg-sky-50/70", dark: "bg-sky-400/[0.07]" },
      "ink"     => { light: "bg-stone-100/80", dark: "bg-white/[0.05]" },
      "gold"    => { light: "bg-amber-50/80", dark: "bg-amber-400/[0.07]" },
      "forest"  => { light: "bg-emerald-50/70", dark: "bg-emerald-400/[0.07]" },
      "rose"    => { light: "bg-rose-50/70", dark: "bg-rose-400/[0.07]" },
      "violet"  => { light: "bg-violet-50/70", dark: "bg-violet-400/[0.07]" },
      "copper"  => { light: "bg-orange-50/70", dark: "bg-orange-400/[0.07]" },
      "indigo"  => { light: "bg-indigo-50/70", dark: "bg-indigo-400/[0.07]" },
      "teal"    => { light: "bg-teal-50/70", dark: "bg-teal-400/[0.07]" },
      "crimson" => { light: "bg-red-50/70", dark: "bg-red-400/[0.07]" },
      "plum"    => { light: "bg-fuchsia-50/70", dark: "bg-fuchsia-400/[0.07]" },
      "olive"   => { light: "bg-lime-50/70", dark: "bg-lime-400/[0.07]" }
    }.freeze

    private_constant :ACCENT_COLORS, :ACCENT_TEXT, :ACCENT_BUTTON, :CTA_BAND, :ACCENT_SOFT, :ACCENT_RING, :ACCENT_DOT,
                     :LINK_HOVER, :PLACEHOLDER, :PLACEHOLDER_BLOB, :ACCENT_SURFACE
  end
end
