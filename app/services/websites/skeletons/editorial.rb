# frozen_string_literal: true

module Websites
  module Skeletons
    module Editorial
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "editorial_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Fall campaign",
                "headline" => "Move like you mean the next mile",
                "subhead" => "A collection cut for weather, speed, and the hour before the city wakes.",
                "primary_label" => "Shop the drop",
                "primary_href" => "stories",
                "tone" => "dark"
              }
            },
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "On track",
                "headline" => "Carbon. Knit. No extra.",
                "subhead" => "A racing layer that forgets it is clothing the moment you hit pace.",
                "primary_label" => "See the film",
                "primary_href" => "https://example.com/campaign",
                "tone" => "dark"
              }
            },
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "City pack",
                "headline" => "From the last meeting to the first hill",
                "subhead" => "Pieces that look like clothes and perform like kit.",
                "primary_label" => "Read the stories",
                "primary_href" => "stories",
                "tone" => "dark"
              }
            },
            {
              "type" => "card_grid",
              "props" => {
                "heading" => "This season",
                "subhead" => "Three stories. One standard of make.",
                "cards" => [
                  { "title" => "Dawn relay", "body" => "A 4 a.m. handoff across the bridges. Shot in one take, worn in the weather that showed up.", "href" => "stories" },
                  { "title" => "Studio miles", "body" => "Treadmill, playlist, no windows. The kit that still looks like itself at midnight.", "href" => "stories" },
                  { "title" => "Sunday long", "body" => "Coffee, a loop, a hill that always wins. Clothes that dry before you get home.", "href" => "about" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Find it on the floor",
                "body" => "The campaign lives in stores this month — not only on a screen.",
                "button_label" => "Store hours",
                "button_href" => "about"
              }
            }
          ]
        },
        {
          "title" => "Stories",
          "slug" => "stories",
          "home" => false,
          "nav_visible" => true,
          "role" => "stories",
          "layout_key" => "editorial_stories",
          "sections" => [
            {
              "type" => "card_grid",
              "props" => {
                "heading" => "Field notes",
                "subhead" => "Athletes, streets, and the clothes in between.",
                "cards" => [
                  { "title" => "The hour before light", "body" => "Lina runs the ridge because the city is still a rumor. The jacket is the only loud thing she wears.", "href" => "about" },
                  { "title" => "Track night", "body" => "A borrowed lane, a borrowed watch, a kit that does not ask for a logo close-up.", "href" => "about" },
                  { "title" => "After the tape", "body" => "What you put on when the race is over and the night is not. Soft. Honest. Still fast if you need it.", "href" => "about" }
                ]
              }
            },
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "Why we shoot in weather",
                "body" => "Gloss is easy. We wait for rain because that is when you learn if a seam is a seam or a suggestion.\n\nEvery still in this campaign was made on a day we could not reschedule. The clothes had to work. That is the only brief."
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
          "layout_key" => "presence_about",
          "sections" => [
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "A house that still cuts patterns by hand",
                "body" => "The machines are new. The table is not. We drape on people who run, then we cut again. If it only looks fast, it does not leave the floor.",
                "image_side" => "left"
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "I forgot I had it on. That is the whole review.",
                "attribution" => "Amina Cole",
                "role" => "Marathon, London"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
