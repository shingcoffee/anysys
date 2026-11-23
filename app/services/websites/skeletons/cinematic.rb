# frozen_string_literal: true

module Websites
  module Skeletons
    module Cinematic
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "cinematic_home",
          "sections" => [
            {
              "type" => "showcase_tiles",
              "props" => {
                "tiles" => [
                  {
                    "kicker" => "New",
                    "title" => "The quietest machine in the room",
                    "body" => "Milled from a single piece. Tuned until the only sound is the work.",
                    "primary_label" => "Learn more",
                    "primary_href" => "about",
                    "secondary_label" => "Compare",
                    "secondary_href" => "compare",
                    "tone" => "dark",
                    "size" => "full"
                  },
                  {
                    "title" => "Color that holds in noon light",
                    "body" => "A display that does not argue with the window. Text stays text. Film stays film.",
                    "primary_label" => "Learn more",
                    "primary_href" => "about",
                    "secondary_label" => "Watch the film",
                    "secondary_href" => "https://example.com/film",
                    "tone" => "light",
                    "size" => "full"
                  },
                  {
                    "title" => "All-day, then some",
                    "body" => "Through the edit, the flight and the last note at midnight.",
                    "primary_label" => "Compare models",
                    "primary_href" => "compare",
                    "tone" => "light",
                    "size" => "half"
                  },
                  {
                    "kicker" => "Studio",
                    "title" => "Made for the long call",
                    "body" => "Cameras, mics and speakers tuned as one.",
                    "primary_label" => "Learn more",
                    "primary_href" => "about",
                    "tone" => "dark",
                    "size" => "half"
                  }
                ]
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "heading" => "Made to disappear into the day",
                "cells" => [
                  { "span" => "hero", "title" => "A hinge you forget", "body" => "Open it a thousand times. It still meets like the first morning." },
                  { "span" => "wide", "title" => "Keys with travel", "body" => "Deep enough to trust. Quiet enough for a shared table." },
                  { "span" => "unit", "title" => "Studio cameras", "body" => "Center stage. Edge to edge. No crop in the conversation." },
                  { "span" => "unit", "title" => "Air", "body" => "Thermals you do not hear. Performance you feel in the export." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Hold it in a store",
                "body" => "The finish, the weight, the click — none of that lives in a photograph.",
                "button_label" => "Find a studio",
                "button_href" => "contact"
              }
            }
          ]
        },
        {
          "title" => "About",
          "slug" => "about",
          "home" => false,
          "nav_visible" => true,
          "role" => "about",
          "layout_key" => "cinematic_story",
          "sections" => [
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "Designed as a whole object",
                "body" => "We do not add a feature and then find a place for it. The product is drawn once, then drawn again, until every surface has a reason. That takes longer. It is the only way the thing stays itself.",
                "image_side" => "right"
              }
            },
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "The shop",
                "body" => "Aluminum arrives in billets. Glass is laminated on site. Firmware is written on the same floor as the fixtures.\n\nVisitors are welcome in the gallery. The line is not a secret — it is simply not a tour. You will see people working. That is the point."
              }
            }
          ]
        },
        {
          "title" => "Compare",
          "slug" => "compare",
          "home" => false,
          "nav_visible" => true,
          "role" => "compare",
          "layout_key" => "cinematic_compare",
          "sections" => [
            {
              "type" => "comparison_table",
              "props" => {
                "kicker" => "Compare",
                "heading" => "Which one is right for you?",
                "subhead" => "Three sizes, one design language. Every model runs the same software for years.",
                "column_1" => "Air",
                "column_2" => "Pro",
                "column_3" => "Studio",
                "rows" => [
                  { "title" => "Display", "value_1" => "13.6-inch", "value_2" => "14.2-inch", "value_3" => "27-inch" },
                  { "title" => "Battery", "value_1" => "Up to 18 hours", "value_2" => "Up to 22 hours", "value_3" => "—" },
                  { "title" => "Weight", "value_1" => "1.2 kg", "value_2" => "1.6 kg", "value_3" => "6.3 kg" },
                  { "title" => "Studio microphones", "value_1" => "✓", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Fanless design", "value_1" => "✓", "value_2" => "—", "value_3" => "—" },
                  { "title" => "Nano-texture glass", "value_1" => "—", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "From", "value_1" => "$999", "value_2" => "$1,599", "value_3" => "$1,999" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Still deciding?",
                "body" => "Book a session in the gallery and try all three side by side.",
                "button_label" => "Book a session",
                "button_href" => "contact"
              }
            }
          ]
        },
        {
          "title" => "Contact",
          "slug" => "contact",
          "home" => false,
          "nav_visible" => true,
          "role" => "contact",
          "layout_key" => "contact_simple",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Studio and gallery",
                "address" => "One Orchard Place\nGround floor gallery",
                "email" => "studio@example.com",
                "phone" => "+1 555 017 1100",
                "hours" => "Open daily, 10:00–19:00"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
