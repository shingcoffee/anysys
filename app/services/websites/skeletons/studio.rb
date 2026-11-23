# frozen_string_literal: true

module Websites
  module Skeletons
    # Airbnb register: a warm hero, a rated grid of stays, one featured
    # house, the full listings, the hosts and a way to write before you go.
    module Studio
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "studio_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Stay with us",
                "headline" => "Rooms that feel like a friend's place",
                "subhead" => "Houses, lofts and cabins hosted by people who actually live there.",
                "primary_label" => "Explore stays",
                "primary_href" => "stays",
                "secondary_label" => "Meet the hosts",
                "secondary_href" => "hosts",
                "tone" => "dark"
              }
            },
            {
              "type" => "listing_grid",
              "props" => {
                "kicker" => "This month",
                "heading" => "Stays guests love",
                "subhead" => "Small, specific and actually available.",
                "aspect" => "square",
                "listings" => [
                  { "title" => "Lakeside cabin", "meta" => "Banff, Canada\nWood stove · lake views", "price" => "$310 night", "rating" => "4.97", "badge" => "Guest favourite", "href" => "stays" },
                  { "title" => "Red cottage on the hill", "meta" => "Faroe Islands\nSea cliffs · sheep for neighbours", "price" => "$180 night", "rating" => "4.92", "href" => "stays" },
                  { "title" => "Beach bungalow", "meta" => "Tulum, Mexico\nSteps to the sand", "price" => "$240 night", "rating" => "4.88", "href" => "stays" },
                  { "title" => "The tiled house", "meta" => "Lisbon, Portugal\nTerrace above the river", "price" => "$165 night", "rating" => "4.95", "href" => "stays" }
                ]
              }
            },
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "A machiya with a garden you eat in",
                "body" => "One family, one street in Kyoto, and one table that has been set for forty years. Kenji sweeps the garden at dawn and will tell you which tram to skip.",
                "image_side" => "right"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Host a stay",
                "body" => "If the room is already beautiful, we will help people find it.",
                "button_label" => "Talk to us",
                "button_href" => "contact"
              }
            }
          ]
        },
        {
          "title" => "Stays",
          "slug" => "stays",
          "home" => false,
          "nav_visible" => true,
          "role" => "stays",
          "layout_key" => "studio_stays",
          "sections" => [
            {
              "type" => "listing_grid",
              "props" => {
                "kicker" => "Stays",
                "heading" => "Places you can book",
                "subhead" => "Every stay is a real home with a named host. Prices include cleaning and fees.",
                "aspect" => "square",
                "listings" => [
                  { "title" => "Lakeside cabin", "meta" => "Banff, Canada", "price" => "$310 night", "rating" => "4.97", "badge" => "Guest favourite", "href" => "contact" },
                  { "title" => "Red cottage on the hill", "meta" => "Faroe Islands", "price" => "$180 night", "rating" => "4.92", "href" => "contact" },
                  { "title" => "Beach bungalow", "meta" => "Tulum, Mexico", "price" => "$240 night", "rating" => "4.88", "href" => "contact" },
                  { "title" => "The tiled house", "meta" => "Lisbon, Portugal", "price" => "$165 night", "rating" => "4.95", "href" => "contact" },
                  { "title" => "Cabin at the tree line", "meta" => "Hood River, Oregon", "price" => "$210 night", "rating" => "4.90", "href" => "contact" },
                  { "title" => "The machiya", "meta" => "Kyoto, Japan", "price" => "$230 night", "rating" => "4.99", "badge" => "Rare find", "href" => "contact" },
                  { "title" => "Forest hideaway", "meta" => "Olympic Peninsula, Washington", "price" => "$150 night", "rating" => "4.86", "href" => "contact" },
                  { "title" => "Villa with a pool", "meta" => "Mallorca, Spain", "price" => "$420 night", "rating" => "4.93", "href" => "contact" }
                ]
              }
            },
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "How booking works",
                "body" => "Write to the host. Agree on dates. Pay when both sides are sure. No anonymous listings, no surprise fees."
              }
            }
          ]
        },
        {
          "title" => "Hosts",
          "slug" => "hosts",
          "home" => false,
          "nav_visible" => true,
          "role" => "team",
          "layout_key" => "studio_hosts",
          "sections" => [
            {
              "type" => "team_grid",
              "props" => {
                "heading" => "People who keep the keys",
                "people" => [
                  { "name" => "Ines Costa", "role" => "Lisbon", "bio" => "Opens the terrace when the wind is kind. Leaves oranges on the table." },
                  { "name" => "Kenji Mori", "role" => "Kyoto", "bio" => "Sweeps the garden at dawn. Will tell you which tram to skip." },
                  { "name" => "Nora Blake", "role" => "Banff", "bio" => "Splits the firewood and leaves a trail map on the door." }
                ]
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "kicker" => "Guests",
                "heading" => "What people write afterwards",
                "items" => [
                  { "quote" => "It felt like staying with a friend who happens to own the best view in Lisbon.", "name" => "Hannah", "role" => "Stayed in the tiled house" },
                  { "quote" => "Kenji's breakfast alone was worth the flight.", "name" => "Marco", "role" => "Stayed in the machiya" },
                  { "quote" => "We woke up to snow on the lake and did not leave the cabin for two days.", "name" => "Priya", "role" => "Stayed in the lakeside cabin" }
                ]
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
          "layout_key" => "studio_contact",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Write before you travel",
                "address" => "We answer from the cities where the stays are.",
                "email" => "stays@example.com",
                "phone" => "",
                "hours" => "Weekdays, local morning."
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "A stay, not a listing",
                "body" => "Tell us the dates and the kind of quiet you want — or browse what is open now.",
                "button_label" => "Browse stays",
                "button_href" => "stays"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
