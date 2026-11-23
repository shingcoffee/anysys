# frozen_string_literal: true

module Websites
  module Skeletons
    # Aesop register: quiet type, one product story, a journal, a visit.
    module Atelier
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "atelier_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Formulations",
                "headline" => "Skin, considered slowly",
                "subhead" => "A small range. Precise ingredients. Nothing added to fill the shelf.",
                "primary_label" => "Read the journal",
                "primary_href" => "journal",
                "secondary_label" => "Visit",
                "secondary_href" => "visit",
                "tone" => "light"
              }
            },
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "The signature",
                "body" => "One fragrance, built to sit close. Citrus at the open, wood once it warms. Made in small batches and dated on the bottle.",
                "image_side" => "right"
              }
            },
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "How to use it",
                "body" => "Morning, on clean skin. Two drops. Wait. The point is not a routine of twelve steps.",
                "image_side" => "left"
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "We would rather retire a formula than explain a compromise.",
                "attribution" => "Atelier note"
              }
            },
            {
              "type" => "gallery",
              "props" => {
                "kicker" => "The collection",
                "heading" => "Made slowly, used daily",
                "items" => [
                  { "caption" => "Resurrection hand balm" },
                  { "caption" => "The Kyoto store" },
                  { "caption" => "Botanical ingredients" },
                  { "caption" => "Refill station" },
                  { "caption" => "Amber glass" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Find a counter",
                "body" => "The product is better in the hand than on a screen.",
                "button_label" => "Plan a visit",
                "button_href" => "visit"
              }
            }
          ]
        },
        {
          "title" => "Journal",
          "slug" => "journal",
          "home" => false,
          "nav_visible" => true,
          "role" => "journal",
          "layout_key" => "atelier_journal",
          "sections" => [
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "On leaving things out",
                "body" => "A formula is a list of refusals. We publish the ones that matter: no filler fragrance, no unlisted dye, no claim we cannot stand behind in the store."
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "If the ingredient needs a footnote, it does not belong in the bottle.",
                "attribution" => "Formulation"
              }
            }
          ]
        },
        {
          "title" => "Visit",
          "slug" => "visit",
          "home" => false,
          "nav_visible" => true,
          "role" => "visit",
          "layout_key" => "atelier_visit",
          "sections" => [
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Stores",
                "heading" => "Each room is designed for its street",
                "subhead" => "Local architects, local materials, and the same sink at the back of every store.",
                "places" => [
                  { "name" => "Mercer Street", "address" => "18 Mercer Street\nNew York, NY", "hours" => "Tuesday–Saturday 11:00–19:00\nSunday 12:00–17:00", "phone" => "+1 555 018 4410", "button_label" => "Get directions", "button_href" => "https://example.com/stores/mercer" },
                  { "name" => "Marylebone", "address" => "42 Marylebone High Street\nLondon W1U", "hours" => "Monday–Saturday 10:00–19:00", "phone" => "+44 20 5555 0181", "button_label" => "Get directions", "button_href" => "https://example.com/stores/marylebone" },
                  { "name" => "Aoyama", "address" => "5-3-2 Minami-Aoyama\nTokyo", "hours" => "Daily 11:00–20:00", "phone" => "+81 3 5555 0186", "button_label" => "Get directions", "button_href" => "https://example.com/stores/aoyama" }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "The counter",
                "address" => "18 Mercer Street\nGround floor",
                "email" => "counter@example.com",
                "phone" => "+1 555 018 4410",
                "hours" => "Tuesday–Saturday, 11:00–19:00\nSunday, 12:00–17:00"
              }
            },
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "What to expect",
                "body" => "A short conversation. Samples if you want them. No one will follow you to the door."
              }
            }
          ]
        }
      ].freeze
    end
  end
end
