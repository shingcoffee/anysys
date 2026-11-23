# frozen_string_literal: true

module Websites
  # Named, curated website themes. Each preset is a complete Websites::Theme
  # token set; the site stores the tokens plus `preset` so owners can start
  # from a named look and fine-tune. Names/descriptions are I18n
  # (website.themes.<key>.*).
  module ThemePresets
    DEFAULT_KEY = "meridian"

    PRESETS = {
      "linen" => { "appearance" => "light", "accent" => "gold", "type" => "classic", "density" => "spacious", "corners" => "soft", "neutral" => "warm" },
      "porcelain" => { "appearance" => "light", "accent" => "ink", "type" => "gallery", "density" => "spacious", "corners" => "soft", "neutral" => "warm" },
      "meridian" => { "appearance" => "light", "accent" => "indigo", "type" => "sans", "density" => "compact", "corners" => "soft", "neutral" => "cool" },
      "glacier" => { "appearance" => "light", "accent" => "teal", "type" => "sans", "density" => "compact", "corners" => "soft", "neutral" => "cool" },
      "midnight" => { "appearance" => "dark", "accent" => "azure", "type" => "sans", "density" => "compact", "corners" => "soft", "neutral" => "cool" },
      "aurora" => { "appearance" => "dark", "accent" => "violet", "type" => "modern", "density" => "compact", "corners" => "round", "neutral" => "cool" },
      "monochrome" => { "appearance" => "light", "accent" => "ink", "type" => "grotesk", "density" => "compact", "corners" => "sharp", "neutral" => "neutral" },
      "obsidian" => { "appearance" => "dark", "accent" => "ink", "type" => "grotesk", "density" => "compact", "corners" => "sharp", "neutral" => "neutral" },
      "noir" => { "appearance" => "dark", "accent" => "ink", "type" => "display", "density" => "spacious", "corners" => "sharp", "neutral" => "neutral" },
      "broadsheet" => { "appearance" => "light", "accent" => "ink", "type" => "serif", "density" => "spacious", "corners" => "sharp", "neutral" => "warm" },
      "almanac" => { "appearance" => "light", "accent" => "copper", "type" => "serif", "density" => "spacious", "corners" => "sharp", "neutral" => "warm" },
      "gilded" => { "appearance" => "dark", "accent" => "gold", "type" => "elegant", "density" => "spacious", "corners" => "sharp", "neutral" => "warm" },
      "terracotta" => { "appearance" => "light", "accent" => "copper", "type" => "classic", "density" => "spacious", "corners" => "soft", "neutral" => "warm" },
      "ember" => { "appearance" => "light", "accent" => "copper", "type" => "grotesk", "density" => "spacious", "corners" => "soft", "neutral" => "warm" },
      "riviera" => { "appearance" => "light", "accent" => "teal", "type" => "elegant", "density" => "spacious", "corners" => "soft", "neutral" => "warm" },
      "coral" => { "appearance" => "light", "accent" => "rose", "type" => "geometric", "density" => "spacious", "corners" => "round", "neutral" => "neutral" },
      "blossom" => { "appearance" => "light", "accent" => "rose", "type" => "elegant", "density" => "spacious", "corners" => "round", "neutral" => "warm" },
      "sage" => { "appearance" => "light", "accent" => "forest", "type" => "geometric", "density" => "spacious", "corners" => "round", "neutral" => "warm" },
      "sandstone" => { "appearance" => "light", "accent" => "gold", "type" => "geometric", "density" => "spacious", "corners" => "round", "neutral" => "warm" },
      "orchard" => { "appearance" => "light", "accent" => "olive", "type" => "display", "density" => "spacious", "corners" => "round", "neutral" => "warm" },
      "academy" => { "appearance" => "light", "accent" => "crimson", "type" => "classic", "density" => "spacious", "corners" => "soft", "neutral" => "neutral" },
      "prism" => { "appearance" => "light", "accent" => "plum", "type" => "modern", "density" => "spacious", "corners" => "round", "neutral" => "neutral" },
      "exhibit" => { "appearance" => "light", "accent" => "ink", "type" => "expressive", "density" => "compact", "corners" => "sharp", "neutral" => "warm" },
      "pulse" => { "appearance" => "dark", "accent" => "crimson", "type" => "expressive", "density" => "compact", "corners" => "sharp", "neutral" => "neutral" },
      "stage" => { "appearance" => "dark", "accent" => "plum", "type" => "modern", "density" => "compact", "corners" => "round", "neutral" => "neutral" },
      "nightshift" => { "appearance" => "dark", "accent" => "forest", "type" => "grotesk", "density" => "compact", "corners" => "round", "neutral" => "neutral" },
      "canopy" => { "appearance" => "dark", "accent" => "forest", "type" => "display", "density" => "spacious", "corners" => "soft", "neutral" => "warm" }
    }.freeze

    module_function

    def keys
      PRESETS.keys
    end

    def known?(key)
      PRESETS.key?(key.to_s)
    end

    def tokens(key)
      PRESETS.fetch(key.to_s) { PRESETS.fetch(DEFAULT_KEY) }.dup
    end

    def theme(key)
      resolved = known?(key) ? key.to_s : DEFAULT_KEY
      Websites::Theme.new(tokens(resolved).merge("preset" => resolved))
    end

    def name(key)
      I18n.t("website.themes.#{key}.name")
    end

    def description(key)
      I18n.t("website.themes.#{key}.description")
    end
  end
end
