# frozen_string_literal: true

module Websites
  module Skeletons
    # Tesla register: a home that is nothing but stacked product tiles, a
    # model comparison, charging, and studios to book a drive.
    module Voltage
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "voltage_home",
          "sections" => [
            {
              "type" => "showcase_tiles",
              "props" => {
                "tiles" => [
                  {
                    "kicker" => "New",
                    "title" => "Model Aero",
                    "body" => "Up to 410 miles of range. Built for the long way round.",
                    "primary_label" => "Order now",
                    "primary_href" => "models",
                    "secondary_label" => "Book a test drive",
                    "secondary_href" => "visit",
                    "tone" => "light",
                    "size" => "full"
                  },
                  {
                    "title" => "Model Terra",
                    "body" => "Seven seats, a flat floor and a tow rating that means it.",
                    "primary_label" => "Order now",
                    "primary_href" => "models",
                    "secondary_label" => "Compare models",
                    "secondary_href" => "models",
                    "tone" => "dark",
                    "size" => "full"
                  },
                  {
                    "title" => "Roadster",
                    "body" => "Zero to sixty before you finish the sentence.",
                    "primary_label" => "Reserve",
                    "primary_href" => "models",
                    "tone" => "light",
                    "size" => "half"
                  },
                  {
                    "title" => "Studio Edition",
                    "body" => "Night paint, carbon trim, numbered to 500.",
                    "primary_label" => "Learn more",
                    "primary_href" => "models",
                    "tone" => "dark",
                    "size" => "half"
                  },
                  {
                    "kicker" => "Energy",
                    "title" => "Power the whole house",
                    "body" => "Solar on the roof, a battery in the garage, the car in the drive — one app for all three.",
                    "primary_label" => "Get a quote",
                    "primary_href" => "charging",
                    "secondary_label" => "How charging works",
                    "secondary_href" => "charging",
                    "tone" => "dark",
                    "size" => "full"
                  }
                ]
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "410 mi", "label" => "longest range, EPA est." },
                  { "value" => "15 min", "label" => "to add 200 miles" },
                  { "value" => "50k+", "label" => "fast chargers" },
                  { "value" => "5★", "label" => "safety rating, every model" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Drive one before you decide",
                "body" => "Book thirty minutes at a studio near you. No salesperson in the passenger seat.",
                "button_label" => "Book a test drive",
                "button_href" => "visit"
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
          "layout_key" => "voltage_models",
          "sections" => [
            {
              "type" => "hero_centered",
              "props" => {
                "eyebrow" => "Compare",
                "headline" => "Find the one that fits your life",
                "subhead" => "Three cars, one platform. Every model charges on the same network and improves with every update.",
                "primary_label" => "Order online",
                "primary_href" => "https://example.com/order",
                "secondary_label" => "Book a test drive",
                "secondary_href" => "visit"
              }
            },
            {
              "type" => "comparison_table",
              "props" => {
                "kicker" => "Specifications",
                "heading" => "Compare models",
                "subhead" => "Estimates for the long-range configuration of each model.",
                "column_1" => "Aero",
                "column_2" => "Terra",
                "column_3" => "Roadster",
                "rows" => [
                  { "title" => "Range (EPA est.)", "value_1" => "410 mi", "value_2" => "350 mi", "value_3" => "620 mi" },
                  { "title" => "0–60 mph", "value_1" => "3.1 s", "value_2" => "3.8 s", "value_3" => "1.9 s" },
                  { "title" => "Top speed", "value_1" => "155 mph", "value_2" => "149 mph", "value_3" => "250 mph" },
                  { "title" => "Seating", "value_1" => "5", "value_2" => "7", "value_3" => "4" },
                  { "title" => "Cargo", "value_1" => "28 cu ft", "value_2" => "88 cu ft", "value_3" => "12 cu ft" },
                  { "title" => "Dual-motor all-wheel drive", "value_1" => "✓", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Tow package", "value_1" => "—", "value_2" => "✓", "value_3" => "—" },
                  { "title" => "Starting price", "value_1" => "$44,990", "value_2" => "$59,990", "value_3" => "$199,000" }
                ]
              }
            },
            {
              "type" => "alternating_features",
              "props" => {
                "kicker" => "Inside",
                "heading" => "Designed around the driver",
                "items" => [
                  { "title" => "A cabin that feels bigger than it is", "body" => "A single glass roof, a flat floor and one screen where you expect it. Everything else gets out of the way." },
                  { "title" => "Assistance that stays quiet", "body" => "Lane keeping, adaptive cruise and parking that simply work — and tell you plainly when they will not." },
                  { "title" => "Better every month", "body" => "Range, comfort and safety features arrive over the air while the car sleeps in your drive." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Order in under ten minutes",
                "body" => "Choose a model, a colour and a delivery date. Change your mind until the day it ships.",
                "button_label" => "Start your order",
                "button_href" => "https://example.com/order"
              }
            }
          ]
        },
        {
          "title" => "Charging",
          "slug" => "charging",
          "home" => false,
          "nav_visible" => true,
          "role" => "charging",
          "layout_key" => "voltage_charging",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Charging",
                "headline" => "Charge while you do everything else",
                "subhead" => "Plug in at home overnight, or add 200 miles in fifteen minutes on the road.",
                "primary_label" => "Find a charger",
                "primary_href" => "https://example.com/map",
                "secondary_label" => "Talk to a specialist",
                "secondary_href" => "visit",
                "tone" => "dark"
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "50k+", "label" => "fast chargers worldwide" },
                  { "value" => "15 min", "label" => "for 200 miles" },
                  { "value" => "99.9%", "label" => "network uptime" },
                  { "value" => "24/7", "label" => "roadside support" }
                ]
              }
            },
            {
              "type" => "steps",
              "props" => {
                "kicker" => "On the road",
                "heading" => "Plug in. Walk away. Drive on.",
                "items" => [
                  { "title" => "Plan the route", "body" => "Navigation adds charging stops automatically and preheats the battery on the way in." },
                  { "title" => "Plug in", "body" => "No app, no card, no screen to tap. The car and the charger recognise each other." },
                  { "title" => "Pay automatically", "body" => "The session is billed to your account and the receipt lands in the app." }
                ]
              }
            },
            {
              "type" => "faq",
              "props" => {
                "kicker" => "Questions",
                "heading" => "Charging, answered",
                "items" => [
                  { "question" => "Do I need a charger at home?", "answer" => "Most owners install a wall connector and charge overnight. A standard outlet works too, just more slowly." },
                  { "question" => "How much does a fast charge cost?", "answer" => "Prices are shown in the car before you plug in and depend on the site and the time of day." },
                  { "question" => "Can I charge at other networks?", "answer" => "Yes. Every model ships with an adapter for public chargers." }
                ]
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
          "layout_key" => "voltage_visit",
          "sections" => [
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Studios",
                "heading" => "Sit in every model, then take one out",
                "subhead" => "Test drives last thirty minutes and start on the hour. Walk in, or book ahead to choose the model.",
                "places" => [
                  { "name" => "Santa Monica", "address" => "1220 Ocean Avenue\nSanta Monica, CA", "hours" => "Daily 10:00–20:00", "phone" => "+1 310 555 0144", "button_label" => "Book a drive", "button_href" => "https://example.com/drive" },
                  { "name" => "Meatpacking", "address" => "55 Gansevoort Street\nNew York, NY", "hours" => "Daily 10:00–21:00", "phone" => "+1 212 555 0110", "button_label" => "Book a drive", "button_href" => "https://example.com/drive" },
                  { "name" => "Hayes Valley", "address" => "400 Hayes Street\nSan Francisco, CA", "hours" => "Tuesday–Sunday 11:00–19:00", "phone" => "+1 415 555 0126", "button_label" => "Book a drive", "button_href" => "https://example.com/drive" },
                  { "name" => "South Congress", "address" => "1600 South Congress Avenue\nAustin, TX", "hours" => "Daily 10:00–19:00", "phone" => "+1 512 555 0183", "button_label" => "Book a drive", "button_href" => "https://example.com/drive" }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Talk to a product specialist",
                "address" => "3500 Deer Creek Road\nPalo Alto, CA",
                "email" => "hello@example.com",
                "phone" => "+1 650 555 0100",
                "hours" => "Monday–Saturday, 8:00–20:00 PT"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
