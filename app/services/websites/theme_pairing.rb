# frozen_string_literal: true

module Websites
  # The named theme each starter skeleton and layout ships with, chosen for
  # the look of the brand register it was authored in. Layouts cut from a
  # skeleton inherit its theme; standalone layouts carry their own. Platform
  # owners may override per row via website_{skeletons,layouts}.theme_key.
  module ThemePairing
    SKELETONS = {
      "presence" => "linen",
      "saas_landing" => "meridian",
      "cinematic" => "monochrome",
      "editorial" => "pulse",
      "studio" => "coral",
      "product" => "glacier",
      "ledger" => "meridian",
      "signal" => "aurora",
      "atelier" => "porcelain",
      "campus" => "academy",
      "gazette" => "broadsheet",
      "lumen" => "midnight",
      "monograph" => "almanac",
      "terrain" => "canopy",
      "supper" => "gilded",
      "clinic" => "sage",
      "folio" => "exhibit",
      "voyage" => "riviera",
      "kinetic" => "pulse",
      "voltage" => "monochrome",
      "wellspring" => "orchard",
      "summit" => "stage",
      "manor" => "gilded",
      "bloom" => "blossom",
      "roast" => "ember",
      "atrium" => "exhibit",
      "canvas" => "prism",
      "harbor" => "sage",
      "calm" => "sandstone",
      "marque" => "noir",
      "tempo" => "nightshift",
      "quarterly" => "almanac"
    }.freeze

    STANDALONE_LAYOUTS = {
      "article" => "broadsheet",
      "manifesto" => "noir",
      "gallery" => "porcelain",
      "longform" => "almanac",
      "launch" => "prism",
      "pricing" => "meridian",
      "portfolio" => "exhibit",
      "menu" => "terracotta",
      "journal" => "almanac",
      "process" => "sage",
      "showcase" => "monochrome",
      "compare" => "meridian",
      "newsroom" => "broadsheet",
      "listings" => "coral",
      "stores" => "porcelain",
      "heritage" => "academy",
      "conference" => "stage",
      "spotlight" => "monochrome",
      "campaign" => "pulse",
      "tour" => "aurora",
      "impact" => "meridian",
      "why_us" => "sandstone",
      "launch_note" => "obsidian"
    }.freeze

    module_function

    def for_skeleton(key)
      SKELETONS.fetch(key.to_s, Websites::ThemePresets::DEFAULT_KEY)
    end

    def for_layout(key)
      STANDALONE_LAYOUTS.fetch(key.to_s) { for_skeleton(Websites::LayoutFamily.of(key)) }
    end

    def for_catalog(key)
      SKELETONS[key.to_s] || for_layout(key)
    end
  end
end
