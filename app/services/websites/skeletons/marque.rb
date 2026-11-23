# frozen_string_literal: true

module Websites
  module Skeletons
    # Porsche register: luxury automotive, cinematic and dark — a car
    # revealed like a film still, then heritage, then the studio visit.
    module Marque
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "marque_home",
          "sections" => [
            {
              "type" => "announcement",
              "props" => {
                "badge" => "Commission",
                "body" => "The 8S Touring — numbered to 300, painted to order, first deliveries in spring.",
                "link_label" => "Reserve a number",
                "href" => "models",
                "surface" => "muted"
              }
            },
            {
              "type" => "image_banner",
              "props" => {
                "kicker" => "The 8S",
                "headline" => "A touring car that still takes the long way",
                "body" => "Rear engine, a manual if you ask, and a silhouette we have been arguing about since 1963.",
                "button_label" => "Configure",
                "button_href" => "models",
                "height" => "tall",
                "placement" => "bottom"
              }
            },
            {
              "type" => "product_spotlight",
              "props" => {
                "kicker" => "8S Touring",
                "headline" => "Four seats. One conversation with the road.",
                "subhead" => "A cabin cut from a single piece of hide, a wheel that still has spokes, and a sound the neighbours will forgive.",
                "primary_label" => "See the specification",
                "primary_href" => "models",
                "secondary_label" => "Book a drive",
                "secondary_href" => "visit",
                "specs" => [
                  { "value" => "3.8s", "label" => "0–60, Touring S" },
                  { "value" => "194 mph", "label" => "governed, if you insist" },
                  { "value" => "2+2", "label" => "seats that are actually seats" },
                  { "value" => "300", "label" => "cars, then the tools are put away" }
                ],
                "spacing" => "roomy"
              }
            },
            {
              "type" => "showcase_tiles",
              "props" => {
                "tiles" => [
                  {
                    "kicker" => "Sports",
                    "title" => "8S Coupé",
                    "body" => "Two seats, a lower roof, the same engine arguing with the rear axle.",
                    "primary_label" => "Configure",
                    "primary_href" => "models",
                    "secondary_label" => "Compare",
                    "secondary_href" => "models",
                    "tone" => "dark",
                    "size" => "half"
                  },
                  {
                    "kicker" => "Open",
                    "title" => "8S Cabriolet",
                    "body" => "The same line, with the sky as a headliner. A 12-second roof.",
                    "primary_label" => "Configure",
                    "primary_href" => "models",
                    "tone" => "light",
                    "size" => "half"
                  }
                ]
              }
            },
            {
              "type" => "metrics",
              "props" => {
                "kicker" => "The house",
                "heading" => "Numbers we still stand behind",
                "items" => [
                  { "value" => "1963", "label" => "first 8-series", "body" => "The silhouette has been revised, never replaced." },
                  { "value" => "76%", "label" => "of every 8S still on the road", "body" => "We keep the parts. The cars keep their owners." },
                  { "value" => "11", "label" => "minutes to paint a single coat", "body" => "By hand, in the same hall as the first one." },
                  { "value" => "1", "label" => "factory, still", "body" => "Every 8S leaves the same gates. We have not opened a second." }
                ],
                "align" => "center",
                "surface" => "contrast"
              }
            },
            {
              "type" => "collection_rail",
              "props" => {
                "kicker" => "Atelier",
                "heading" => "Finish, hide and the small decisions",
                "subhead" => "Twelve paints, four hides, a wheel you can specify in the original 16-inch.",
                "aspect" => "landscape",
                "items" => [
                  { "title" => "Slate metallic", "meta" => "Paint · 14 hours", "href" => "models" },
                  { "title" => "Oxblood hide", "meta" => "Cabin · full", "href" => "models" },
                  { "title" => "Heritage wheel", "meta" => "16-inch, open", "href" => "models" },
                  { "title" => "Walnut fascia", "meta" => "Open pore", "href" => "models" },
                  { "title" => "Touring trunk", "meta" => "Two cases, fitted", "href" => "models" },
                  { "title" => "Night package", "meta" => "Lamps, badging", "href" => "models" }
                ],
                "align" => "start",
                "surface" => "muted"
              }
            },
            {
              "type" => "cta_split",
              "props" => {
                "kicker" => "Studios",
                "headline" => "Sit in one before you commission it",
                "body" => "An hour with the 8S, no salesperson in the passenger seat. Bring the questions. Leave with a number if it fits.",
                "primary_label" => "Book a drive",
                "primary_href" => "visit",
                "secondary_label" => "Read the house story",
                "secondary_href" => "story",
                "image_side" => "right"
              }
            }
          ]
        },
        {
          "title" => "Models",
          "slug" => "models",
          "home" => false,
          "nav_visible" => true,
          "role" => "models",
          "layout_key" => "marque_models",
          "sections" => [
            {
              "type" => "product_spotlight",
              "props" => {
                "kicker" => "The line",
                "headline" => "Three bodies. One engine family.",
                "subhead" => "Coupé, Touring, Cabriolet. Choose the roof, then the axle, then the hide. Everything else is already decided.",
                "primary_label" => "Start a commission",
                "primary_href" => "https://example.com/configure",
                "secondary_label" => "Book a drive",
                "secondary_href" => "visit",
                "specs" => [
                  { "value" => "Coupé", "label" => "two seats, 1,420 kg" },
                  { "value" => "Touring", "label" => "2+2, 1,510 kg" },
                  { "value" => "Cabriolet", "label" => "two seats, 12-second roof" },
                  { "value" => "Manual", "label" => "still offered, no surcharge" }
                ]
              }
            },
            {
              "type" => "comparison_table",
              "props" => {
                "kicker" => "Specification",
                "heading" => "Side by side",
                "subhead" => "Touring S figures. Other axles on request.",
                "column_1" => "Coupé",
                "column_2" => "Touring",
                "column_3" => "Cabriolet",
                "rows" => [
                  { "title" => "0–60 mph", "value_1" => "3.6 s", "value_2" => "3.8 s", "value_3" => "3.9 s" },
                  { "title" => "Top speed", "value_1" => "198 mph", "value_2" => "194 mph", "value_3" => "190 mph" },
                  { "title" => "Seats", "value_1" => "2", "value_2" => "2+2", "value_3" => "2" },
                  { "title" => "Boot", "value_1" => "4.6 cu ft", "value_2" => "12 cu ft", "value_3" => "4.1 cu ft" },
                  { "title" => "Manual", "value_1" => "✓", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Commission from", "value_1" => "$148,000", "value_2" => "$164,000", "value_3" => "$172,000" }
                ],
                "align" => "start",
                "surface" => "muted"
              }
            },
            {
              "type" => "feature_tabs",
              "props" => {
                "kicker" => "On the road",
                "heading" => "What the 8S is for",
                "tabs" => [
                  { "label" => "Touring", "title" => "Dawn starts and a second breakfast", "body" => "A tank that lasts a country, seats that last a day, and a stereo we almost left out." },
                  { "label" => "Pass", "title" => "The road that justifies the engine", "body" => "Rear weight, a short wheelbase, and steering that still talks. Take the long way down." },
                  { "label" => "City", "title" => "A weekend car that can do a Tuesday", "body" => "Rear visibility, a turning circle we measured in streets, not brochures." },
                  { "label" => "Night", "title" => "Lamps that look like the first ones", "body" => "Four ovals, a glow we have not modernised, on purpose." }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Commission takes fourteen weeks",
                "body" => "A deposit holds a number. You can change paint and hide until week six. After that, the hall starts.",
                "button_label" => "Start a commission",
                "button_href" => "https://example.com/configure"
              }
            }
          ]
        },
        {
          "title" => "Story",
          "slug" => "story",
          "home" => false,
          "nav_visible" => true,
          "role" => "story",
          "layout_key" => "marque_story",
          "sections" => [
            {
              "type" => "timeline",
              "props" => {
                "kicker" => "The house",
                "heading" => "Sixty years of one argument",
                "subhead" => "The engine belongs behind the seats. Everything else is a conversation.",
                "items" => [
                  { "date" => "1963", "title" => "The first 8", "body" => "A road car built because the race car needed a sibling. Two hundred were promised. Four hundred were sold." },
                  { "date" => "1978", "title" => "Touring", "body" => "Rear seats that adults would use, and a roof that did not spoil the line." },
                  { "date" => "1996", "title" => "We kept the factory", "body" => "Offers to move the line were declined. The hall stayed." },
                  { "date" => "2014", "title" => "Hybrid, quietly", "body" => "A second motor, no badge. The sound is still the first thing you notice." },
                  { "date" => "2026", "title" => "8S, numbered", "body" => "Three hundred Tourings. Then the tools go back on the wall." }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "image_banner",
              "props" => {
                "kicker" => "The hall",
                "headline" => "Every 8S still leaves through the same gates",
                "body" => "Paint, hide and a final drive on the ring road. We have not opened a second factory.",
                "button_label" => "Visit the studio",
                "button_href" => "visit",
                "height" => "medium",
                "placement" => "center"
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "Make it lower. Then make it honest. Then stop.",
                "attribution" => "Founder's note",
                "role" => "Pinned above the design loft",
                "surface" => "contrast"
              }
            },
            {
              "type" => "gallery",
              "props" => {
                "kicker" => "Archive",
                "heading" => "The line, from the first clay",
                "items" => [
                  { "caption" => "Clay, 1962" },
                  { "caption" => "The first hall" },
                  { "caption" => "Touring roof jig" },
                  { "caption" => "Night lamps, 1974" },
                  { "caption" => "Hide room" }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "We do not launch every year",
                "body" => "A new 8-series arrives when the last argument is finished — not when a calendar says so. If you are waiting for a refresh, wait. The one on the floor is the one we mean."
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
          "layout_key" => "marque_visit",
          "sections" => [
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Studios",
                "heading" => "An hour with the car, then the road",
                "subhead" => "Drives start on the hour. Bring a licence. Leave the pitch at the door.",
                "places" => [
                  { "name" => "Stuttgart Atelier", "address" => "14 Werkstrasse\nStuttgart", "hours" => "Tuesday–Saturday 10:00–18:00", "phone" => "+49 711 555 010", "button_label" => "Book a drive", "button_href" => "https://example.com/drive" },
                  { "name" => "Mayfair", "address" => "18 Bruton Street\nLondon", "hours" => "Monday–Saturday 10:00–19:00", "phone" => "+44 20 7555 0144", "button_label" => "Book a drive", "button_href" => "https://example.com/drive" },
                  { "name" => "Beverly Hills", "address" => "9876 Wilshire Boulevard\nBeverly Hills, CA", "hours" => "Daily 10:00–19:00", "phone" => "+1 310 555 0188", "button_label" => "Book a drive", "button_href" => "https://example.com/drive" }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Commissions and heritage",
                "address" => "14 Werkstrasse\nStuttgart",
                "email" => "atelier@example.com",
                "phone" => "+49 711 555 010",
                "hours" => "Weekdays, 9:00–17:00 CET"
              }
            },
            {
              "type" => "cta_split",
              "props" => {
                "kicker" => "Heritage",
                "headline" => "We still service the first 8",
                "body" => "Parts, a rebuild, a letter from the archive. If the car is ours, the hall will still know it.",
                "primary_label" => "Write to heritage",
                "primary_href" => "https://example.com/heritage",
                "secondary_label" => "Read the house story",
                "secondary_href" => "story",
                "image_side" => "left",
                "surface" => "muted"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
