# frozen_string_literal: true

module Websites
  # Editor schema for each SectionKit type: which props the composer renders,
  # in what order, and with which control. Labels are I18n keys resolved at
  # render time.
  module SectionFields
    LABEL_KEYS = {
      "kicker" => "website.admin.pages.form.fields.kicker",
      "headline" => "website.admin.pages.form.fields.headline",
      "subhead" => "website.admin.pages.form.fields.subhead",
      "primary_label" => "website.admin.pages.form.fields.primary_label",
      "primary_href" => "website.admin.pages.form.fields.primary_href",
      "secondary_label" => "website.admin.pages.form.fields.secondary_label",
      "secondary_href" => "website.admin.pages.form.fields.secondary_href",
      "image_url" => "website.admin.pages.form.fields.image_url",
      "media_mode" => "website.admin.pages.form.fields.media_mode",
      "example_label" => "website.admin.pages.form.fields.example_label",
      "prompt_label" => "website.admin.pages.form.fields.prompt_label",
      "prompt" => "website.admin.pages.form.fields.prompt",
      "review_note" => "website.admin.pages.form.fields.review_note",
      "output_label" => "website.admin.pages.form.fields.output_label",
      "status" => "common.labels.status",
      "featured_label" => "website.admin.pages.form.fields.featured_label",
      "visual_url" => "website.admin.pages.form.fields.visual_url",
      "tone" => "website.admin.pages.form.fields.tone",
      "eyebrow" => "website.admin.pages.form.fields.eyebrow",
      "heading" => "website.admin.settings.footer.column_heading",
      "body" => "website.admin.pages.form.fields.body",
      "label" => "website.admin.settings.footer.link_label",
      "value" => "website.admin.pages.form.fields.value",
      "span" => "website.admin.pages.form.fields.span",
      "title" => "website.admin.pages.form.title",
      "href" => "website.admin.pages.form.fields.href",
      "name" => "common.labels.name",
      "role" => "common.labels.role",
      "bio" => "website.admin.pages.form.fields.bio",
      "quote" => "website.admin.pages.form.fields.quote",
      "attribution" => "website.admin.pages.form.fields.attribution",
      "question" => "website.admin.pages.form.fields.question",
      "answer" => "website.admin.pages.form.fields.answer",
      "button_label" => "website.admin.pages.form.fields.button_label",
      "button_href" => "website.admin.pages.form.fields.button_href",
      "image_side" => "website.admin.pages.form.fields.image_side",
      "address" => "website.admin.pages.form.fields.address",
      "email" => "common.labels.email",
      "phone" => "website.admin.pages.form.fields.phone",
      "hours" => "website.admin.pages.form.fields.hours",
      "items" => "website.admin.pages.form.fields.items",
      "cells" => "website.admin.pages.form.fields.cells",
      "cards" => "website.admin.pages.form.fields.cards",
      "people" => "website.admin.pages.form.fields.people",
      "tiers" => "website.admin.pages.form.fields.tiers",
      "price" => "website.admin.pages.form.fields.price",
      "cadence" => "website.admin.pages.form.fields.cadence",
      "features" => "website.admin.pages.form.fields.features",
      "caption" => "website.admin.pages.form.fields.caption",
      "highlight" => "website.admin.pages.form.fields.highlight",
      "tiles" => "website.admin.pages.form.fields.tiles",
      "size" => "website.admin.pages.form.fields.size",
      "date" => "website.admin.pages.form.fields.date",
      "stories" => "website.admin.pages.form.fields.stories",
      "byline" => "website.admin.pages.form.fields.byline",
      "rows" => "website.admin.pages.form.fields.rows",
      **SectionKit::COMPARISON_COLUMNS.to_h { |n| ["column_#{n}", "website.admin.pages.form.fields.column_#{n}"] },
      **SectionKit::COMPARISON_COLUMNS.to_h { |n| ["value_#{n}", "website.admin.pages.form.fields.value_#{n}"] },
      "listings" => "website.admin.pages.form.fields.listings",
      "aspect" => "website.admin.pages.form.fields.aspect",
      "meta" => "website.admin.pages.form.fields.meta",
      "rating" => "website.admin.pages.form.fields.rating",
      "badge" => "website.admin.pages.form.fields.badge",
      "sessions" => "website.admin.pages.form.fields.sessions",
      "time" => "website.admin.pages.form.fields.time",
      "speaker" => "website.admin.pages.form.fields.speaker",
      "track" => "website.admin.pages.form.fields.track",
      "places" => "website.admin.pages.form.fields.places",
      "link_label" => "website.admin.pages.form.fields.link_label",
      "specs" => "website.admin.pages.form.fields.specs",
      "tabs" => "website.admin.pages.form.fields.tabs",
      "height" => "website.admin.pages.form.fields.height",
      "placement" => "website.admin.pages.form.fields.placement",
      "surface" => "website.admin.pages.form.fields.surface",
      "spacing" => "website.admin.pages.form.fields.spacing",
      "align" => "website.admin.pages.form.fields.align"
    }.freeze

    OPTION_LABEL_KEYS = {
      "media_mode" => SectionKit::MEDIA_MODES.to_h { |mode| [mode, "website.admin.pages.form.media_modes.#{mode}"] },
      "tone" => {
        "light" => "website.admin.settings.theme.light",
        "dark" => "website.admin.settings.theme.dark"
      },
      "span" => {
        "hero" => "website.admin.pages.form.spans.hero",
        "wide" => "website.admin.pages.form.spans.wide",
        "unit" => "website.admin.pages.form.spans.unit"
      },
      "image_side" => {
        "left" => "website.admin.pages.form.image_sides.left",
        "right" => "website.admin.pages.form.image_sides.right"
      },
      "highlight" => {
        "standard" => "website.admin.pages.form.highlights.standard",
        "featured" => "website.admin.pages.form.highlights.featured"
      },
      "size" => SectionKit::TILE_SIZES.to_h { |size| [size, "website.admin.pages.form.sizes.#{size}"] },
      "aspect" => SectionKit::ASPECTS.to_h { |aspect| [aspect, "website.admin.pages.form.aspects.#{aspect}"] },
      "height" => SectionKit::BANNER_HEIGHTS.to_h { |height| [height, "website.admin.pages.form.heights.#{height}"] },
      "placement" => SectionKit::PLACEMENTS.to_h { |placement| [placement, "website.admin.pages.form.placements.#{placement}"] },
      "surface" => SectionKit::SURFACES.to_h { |surface| [surface, "website.admin.pages.form.surfaces.#{surface}"] },
      "spacing" => SectionKit::SPACINGS.to_h { |spacing| [spacing, "website.admin.pages.form.spacings.#{spacing}"] },
      "align" => SectionKit::ALIGNS.to_h { |align| [align, "website.admin.pages.form.aligns.#{align}"] }
    }.freeze

    module_function

    def string(key) = { key: key, kind: :string }
    def area(key, hint: nil) = { key: key, kind: :textarea, hint: hint }
    def select(key, options) = { key: key, kind: :select, options: options }
    def array(key, min:, max:, item_fields:) = { key: key, kind: :array, min: min, max: max, item_fields: item_fields }

    def header = [string("kicker"), string("heading"), area("subhead")]
    def button_pair(key) = [string("#{key}_label"), string("#{key}_href")]

    # Look-and-feel overrides every section accepts; kept apart from the
    # content schema so the editor can render them as one Style block.
    def style_fields(type)
      return [] unless SectionKit.known?(type)

      keys = SectionKit::STYLE_KEYS.dup
      keys.delete("align") unless SectionKit::ALIGNABLE.include?(type.to_s)
      keys.delete("spacing") if SectionKit::UNSPACED.include?(type.to_s)
      keys.map { |key| select(key, SectionKit.style_options(key)) }
    end

    # Persistence + assistant schema: content fields followed by style fields.
    def full_schema_for(type)
      schema_for(type) + style_fields(type)
    end

    def schema_for(type)
      case type.to_s
      when "announcement"
        [string("badge"), string("body"), string("link_label"), string("href")]
      when "product_spotlight"
        [string("kicker"), string("headline"), area("subhead"), *button_pair("primary"), *button_pair("secondary"),
         string("image_url"), array("specs", min: 0, max: 4, item_fields: [string("value"), string("label")])]
      when "image_banner"
        [string("kicker"), area("headline"), area("body"), string("button_label"), string("button_href"),
         string("image_url"), select("height", SectionKit::BANNER_HEIGHTS), select("placement", SectionKit::PLACEMENTS)]
      when "metrics"
        [*header, array("items", min: 0, max: 4, item_fields: [string("value"), string("label"), area("body")])]
      when "feature_tabs"
        [*header, array("tabs", min: 0, max: 5, item_fields: [string("label"), string("title"), area("body"), string("image_url")])]
      when "split_checklist"
        [string("kicker"), string("heading"), area("body"), string("button_label"), string("button_href"),
         array("items", min: 0, max: 8, item_fields: [string("title"), area("body")])]
      when "collection_rail"
        [*header, select("aspect", SectionKit::ASPECTS),
         array("items", min: 0, max: 12, item_fields: [string("title"), string("meta"), string("image_url"), string("href")])]
      when "cta_split"
        [string("kicker"), string("headline"), area("body"), *button_pair("primary"), *button_pair("secondary"),
         string("image_url"), select("image_side", SectionKit::IMAGE_SIDES)]
      when "hero_cinematic"
        [string("kicker"), string("headline"), area("subhead"), *button_pair("primary"), *button_pair("secondary"),
         string("image_url"), select("tone", SectionKit::TONES)]
      when "hero_split"
        [string("eyebrow"), string("headline"), area("subhead"), *button_pair("primary"), *button_pair("secondary"),
         string("visual_url")]
      when "hero_centered"
        [string("eyebrow"), string("headline"), area("subhead"), *button_pair("primary"), *button_pair("secondary"),
         select("media_mode", SectionKit::MEDIA_MODES), string("image_url")]
      when "ai_preview"
        [*header, string("example_label"), string("prompt_label"), area("prompt"), area("review_note"), string("output_label"),
         array("items", min: 1, max: 4, item_fields: [string("title"), area("body"), string("status")])]
      when "statement"
        [string("kicker"), area("headline"), area("body")]
      when "proof_strip"
        [array("items", min: 4, max: 6, item_fields: [string("label"), string("value")])]
      when "logo_cloud"
        [string("heading"), array("items", min: 0, max: 12, item_fields: [string("name"), string("image_url")])]
      when "showcase_tiles"
        [array("tiles", min: 1, max: 8, item_fields: [
          string("kicker"), string("title"), area("body"), *button_pair("primary"), *button_pair("secondary"),
          string("image_url"), select("tone", SectionKit::TONES), select("size", SectionKit::TILE_SIZES)
        ])]
      when "timeline"
        [*header, array("items", min: 0, max: 16, item_fields: [string("date"), string("title"), area("body")])]
      when "story_index"
        [string("kicker"), string("heading"),
         array("stories", min: 0, max: 12, item_fields: [
           string("kicker"), string("title"), area("body"), string("byline"), string("image_url"), string("href")
         ])]
      when "comparison_table"
        [*header, *SectionKit::COMPARISON_COLUMNS.map { |n| string("column_#{n}") },
         array("rows", min: 0, max: 24, item_fields: [string("title"), *SectionKit::COMPARISON_COLUMNS.map { |n| string("value_#{n}") }])]
      when "listing_grid"
        [*header, select("aspect", SectionKit::ASPECTS),
         array("listings", min: 0, max: 12, item_fields: [
           string("title"), string("meta"), string("price"), string("rating"), string("badge"), string("image_url"), string("href")
         ])]
      when "agenda"
        [*header,
         array("sessions", min: 0, max: 24, item_fields: [
           string("time"), string("title"), string("speaker"), area("body"), string("track")
         ])]
      when "locations"
        [*header,
         array("places", min: 0, max: 12, item_fields: [
           string("name"), area("address"), area("hours"), string("phone"), *button_pair("button"), string("image_url")
         ])]
      when "bento_grid"
        [string("kicker"), string("heading"),
         array("cells", min: 0, max: 8, item_fields: [select("span", SectionKit::SPANS), string("title"), area("body"), string("image_url")])]
      when "alternating_features"
        [string("kicker"), string("heading"),
         array("items", min: 0, max: 8, item_fields: [string("title"), area("body"), string("image_url")])]
      when "feature_grid"
        [*header, array("items", min: 0, max: 12, item_fields: [string("title"), area("body")])]
      when "steps"
        [*header, array("items", min: 0, max: 6, item_fields: [string("title"), area("body")])]
      when "card_grid"
        [*header,
         array("cards", min: 0, max: 12, item_fields: [string("title"), area("body"), string("image_url"), string("href")])]
      when "gallery"
        [*header, array("items", min: 0, max: 12, item_fields: [string("image_url"), string("caption")])]
      when "team_grid"
        [string("kicker"), string("heading"),
         array("people", min: 0, max: 12, item_fields: [string("name"), string("role"), area("bio"), string("image_url")])]
      when "quote"
        [area("quote"), string("attribution"), string("role")]
      when "testimonials"
        [string("kicker"), string("heading"),
         array("items", min: 0, max: 12, item_fields: [area("quote"), string("name"), string("role"), string("image_url")])]
      when "pricing"
        [*header, string("featured_label"),
         array("tiers", min: 0, max: 4, item_fields: [
           string("name"), string("price"), string("cadence"), area("body"), area("features"),
           string("button_label"), string("button_href"), select("highlight", SectionKit::HIGHLIGHTS)
         ])]
      when "price_list"
        [*header, array("items", min: 0, max: 24, item_fields: [string("title"), area("body"), string("price")])]
      when "faq"
        [string("kicker"), string("heading"), array("items", min: 0, max: 20, item_fields: [string("question"), area("answer")])]
      when "cta_band"
        [string("headline"), area("body"), string("button_label"), string("button_href")]
      when "rich_text"
        [string("heading"), area("body", hint: :rich_text)]
      when "split_image_text"
        [string("heading"), area("body"), string("image_url"), select("image_side", SectionKit::IMAGE_SIDES)]
      when "contact_info"
        [string("heading"), area("address"), string("email"), string("phone"), string("hours")]
      else
        []
      end
    end
  end
end
