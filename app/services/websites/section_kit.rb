# frozen_string_literal: true

module Websites
  # Catalog of marketing section types. ViewComponents live under
  # Websites::Sections::*; this module is the schema the composer and
  # contract share.
  module SectionKit
    TYPES = %w[
      announcement
      hero_cinematic
      hero_split
      hero_centered
      product_spotlight
      image_banner
      ai_preview
      statement
      proof_strip
      metrics
      logo_cloud
      showcase_tiles
      bento_grid
      feature_tabs
      alternating_features
      feature_grid
      split_checklist
      steps
      timeline
      card_grid
      collection_rail
      story_index
      gallery
      team_grid
      quote
      testimonials
      pricing
      comparison_table
      price_list
      listing_grid
      agenda
      faq
      cta_band
      cta_split
      rich_text
      split_image_text
      contact_info
      locations
    ].freeze

    COMPARISON_COLUMNS = (1..4).to_a.freeze

    STRING_PROPS = {
      "hero_cinematic" => %w[kicker headline subhead primary_label primary_href secondary_label secondary_href image_url tone],
      "hero_split" => %w[headline subhead primary_label primary_href secondary_label secondary_href visual_url eyebrow],
      "hero_centered" => %w[eyebrow headline subhead primary_label primary_href secondary_label secondary_href image_url media_mode],
      "ai_preview" => %w[kicker heading subhead example_label prompt_label prompt review_note output_label],
      "statement" => %w[kicker headline body],
      "proof_strip" => %w[],
      "logo_cloud" => %w[heading],
      "showcase_tiles" => %w[],
      "bento_grid" => %w[kicker heading],
      "alternating_features" => %w[kicker heading],
      "feature_grid" => %w[kicker heading subhead],
      "steps" => %w[kicker heading subhead],
      "timeline" => %w[kicker heading subhead],
      "card_grid" => %w[kicker heading subhead],
      "story_index" => %w[kicker heading],
      "gallery" => %w[kicker heading subhead],
      "team_grid" => %w[kicker heading],
      "quote" => %w[quote attribution role],
      "testimonials" => %w[kicker heading],
      "pricing" => %w[kicker heading subhead featured_label],
      "comparison_table" => %w[kicker heading subhead] + COMPARISON_COLUMNS.map { |n| "column_#{n}" },
      "price_list" => %w[kicker heading subhead],
      "listing_grid" => %w[kicker heading subhead aspect],
      "agenda" => %w[kicker heading subhead],
      "faq" => %w[kicker heading],
      "cta_band" => %w[headline body button_label button_href],
      "rich_text" => %w[heading body],
      "split_image_text" => %w[heading body image_url image_side],
      "contact_info" => %w[heading address email phone hours],
      "locations" => %w[kicker heading subhead],
      "announcement" => %w[badge body link_label href],
      "product_spotlight" => %w[kicker headline subhead primary_label primary_href secondary_label secondary_href image_url],
      "image_banner" => %w[kicker headline body button_label button_href image_url height placement],
      "metrics" => %w[kicker heading subhead],
      "feature_tabs" => %w[kicker heading subhead],
      "split_checklist" => %w[kicker heading body button_label button_href],
      "collection_rail" => %w[kicker heading subhead aspect],
      "cta_split" => %w[kicker headline body primary_label primary_href secondary_label secondary_href image_url image_side]
    }.freeze

    ARRAY_PROPS = {
      "ai_preview" => "items",
      "proof_strip" => "items",
      "logo_cloud" => "items",
      "showcase_tiles" => "tiles",
      "bento_grid" => "cells",
      "alternating_features" => "items",
      "feature_grid" => "items",
      "steps" => "items",
      "timeline" => "items",
      "card_grid" => "cards",
      "story_index" => "stories",
      "gallery" => "items",
      "team_grid" => "people",
      "testimonials" => "items",
      "pricing" => "tiers",
      "comparison_table" => "rows",
      "price_list" => "items",
      "listing_grid" => "listings",
      "agenda" => "sessions",
      "faq" => "items",
      "locations" => "places",
      "product_spotlight" => "specs",
      "metrics" => "items",
      "feature_tabs" => "tabs",
      "split_checklist" => "items",
      "collection_rail" => "items"
    }.freeze

    HREF_KEYS = %w[primary_href secondary_href href button_href url].freeze
    IMAGE_KEYS = %w[image_url visual_url].freeze

    TONES       = %w[light dark].freeze
    IMAGE_SIDES = %w[left right].freeze
    SPANS       = %w[hero wide unit].freeze
    HIGHLIGHTS  = %w[standard featured].freeze
    TILE_SIZES  = %w[full half].freeze
    ASPECTS     = %w[square portrait landscape].freeze
    MEDIA_MODES = %w[image none].freeze
    BANNER_HEIGHTS = %w[tall medium].freeze
    PLACEMENTS = %w[bottom center].freeze

    # Per-section style overrides shared by every type. "default" (or blank)
    # defers to the site theme. Only header-led types expose alignment.
    SURFACES = %w[default muted contrast accent].freeze
    SPACINGS = %w[default tight roomy].freeze
    ALIGNS   = %w[default start center].freeze
    STYLE_KEYS = %w[surface spacing align].freeze
    ALIGNABLE = %w[
      comparison_table timeline testimonials team_grid pricing card_grid gallery price_list steps feature_grid
      ai_preview faq locations listing_grid agenda bento_grid alternating_features metrics feature_tabs collection_rail
    ].freeze
    # Full-bleed types own their height, so a spacing override has no effect.
    UNSPACED = %w[hero_cinematic showcase_tiles image_banner announcement].freeze

    # Picker grouping. Only keys present in TYPES are surfaced.
    GROUPS = {
      "heroes" => %w[hero_cinematic hero_split hero_centered product_spotlight image_banner statement announcement],
      "stories" => %w[rich_text split_image_text alternating_features feature_tabs feature_grid split_checklist steps timeline agenda],
      "showcase" => %w[ai_preview showcase_tiles bento_grid card_grid collection_rail story_index gallery],
      "proof" => %w[proof_strip metrics logo_cloud quote testimonials],
      "people" => %w[team_grid],
      "offers" => %w[pricing comparison_table price_list listing_grid],
      "closing" => %w[faq cta_band cta_split contact_info locations]
    }.freeze

    module_function

    def groups
      grouped = GROUPS.transform_values { |types| types & TYPES }.reject { |_key, types| types.empty? }
      leftover = TYPES - grouped.values.flatten
      leftover.any? ? grouped.merge("more" => leftover) : grouped
    end

    def known?(type)
      TYPES.include?(type.to_s)
    end

    def style_options(key)
      { "surface" => SURFACES, "spacing" => SPACINGS, "align" => ALIGNS }.fetch(key.to_s)
    end

    # The stored style override, or "default" when blank or unrecognised.
    def style_value(props, key)
      value = props.respond_to?(:[]) ? (props[key.to_s] || props[key.to_sym]).to_s : ""
      style_options(key).include?(value) ? value : "default"
    end

    def component_class(type)
      return unless known?(type)

      "Websites::Sections::#{type.to_s.camelize}Component".constantize
    rescue NameError
      nil
    end
  end
end
