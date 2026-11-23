# frozen_string_literal: true

module Websites
  module Skeletons
    module Supper
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "supper_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Season of the forest",
                "headline" => "Twenty courses from within a day's walk",
                "subhead" => "A tasting menu that follows the calendar of the land around us — foraged, fermented and served at one long table.",
                "primary_label" => "Reserve a table",
                "primary_href" => "visit",
                "secondary_label" => "See the menu",
                "secondary_href" => "menu",
                "tone" => "dark"
              }
            },
            {
              "type" => "statement",
              "props" => {
                "kicker" => "The kitchen",
                "headline" => "We cook what the season gives us, and nothing it does not.",
                "body" => "Our year has three menus: ocean in winter, vegetables in summer, game and forest in autumn. Each is built from ingredients gathered by our own team and a small circle of growers."
              }
            },
            {
              "type" => "gallery",
              "props" => {
                "heading" => "From the pass",
                "items" => [
                  { "caption" => "Beetroot, rose and smoked cream" },
                  { "caption" => "The test kitchen at dawn" },
                  { "caption" => "Wild mushrooms, just in" },
                  { "caption" => "Service, nine o'clock" },
                  { "caption" => "Pine, honey and cultured butter" }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => { "quote" => "Nothing on the plate is there to impress. Everything is there because it was ready.", "attribution" => "Elin Sørensen", "role" => "Head chef" }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Reservations open on the first of the month",
                "body" => "Tables are released at noon for the following three months. Walk-ins welcome at the bar.",
                "button_label" => "Plan your visit",
                "button_href" => "visit"
              }
            }
          ]
        },
        {
          "title" => "Menu",
          "slug" => "menu",
          "home" => false,
          "nav_visible" => true,
          "role" => "menu",
          "layout_key" => "supper_menu",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Autumn menu",
                "headline" => "Game and forest",
                "subhead" => "Served September to December. The menu changes as the forest does — sometimes daily.",
                "primary_label" => "Reserve",
                "primary_href" => "visit"
              }
            },
            {
              "type" => "price_list",
              "props" => {
                "kicker" => "Tasting",
                "heading" => "The autumn menu",
                "subhead" => "Twenty servings over roughly three and a half hours.",
                "items" => [
                  { "title" => "Tasting menu", "body" => "Twenty servings from forest, field and fjord.", "price" => "€450" },
                  { "title" => "Wine pairing", "body" => "Natural and low-intervention wines from small growers.", "price" => "€300" },
                  { "title" => "Juice pairing", "body" => "Pressed, fermented and aged in our own cellar.", "price" => "€175" },
                  { "title" => "Bar menu", "body" => "Six small plates, served at the counter without reservation.", "price" => "€120" }
                ]
              }
            },
            {
              "type" => "feature_grid",
              "props" => {
                "kicker" => "Notes",
                "heading" => "Before you arrive",
                "items" => [
                  { "title" => "Dietary needs", "body" => "Tell us when you book. We cook for allergies, not preferences, on the day." },
                  { "title" => "Timing", "body" => "Please arrive within fifteen minutes of your booking. The menu moves as one." },
                  { "title" => "Children", "body" => "Welcome from age ten, with a shorter menu made just for them." }
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
          "layout_key" => "supper_visit",
          "sections" => [
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "Find us by the water",
                "body" => "We are a ten-minute walk from the harbour, through the old naval yard. Look for the lanterns at the gate.",
                "image_side" => "right"
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Reservations",
                "address" => "Refshalevej 96\n1432 Copenhagen",
                "email" => "reservations@example.com",
                "phone" => "+45 32 96 32 97",
                "hours" => "Tuesday–Saturday\nDinner from 17:00"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
