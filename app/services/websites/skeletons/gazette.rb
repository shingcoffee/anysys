# frozen_string_literal: true

module Websites
  module Skeletons
    # Newspaper register: a ruled front page with a lead story, secondary
    # stories and briefs, then the essay and the masthead.
    module Gazette
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "gazette_home",
          "sections" => [
            {
              "type" => "story_index",
              "props" => {
                "kicker" => "This week",
                "heading" => "The front page",
                "stories" => [
                  { "kicker" => "Reported essay", "title" => "The harbor at night", "body" => "Who keeps a city open after midnight — the pilots, the crane operators and the one diner that never closes.", "byline" => "By Samir Aziz · 14 min read", "href" => "essay" },
                  { "kicker" => "Education", "title" => "A school that kept its shop class", "body" => "Tools, tuition and a principal who refused the easy cut.", "byline" => "By Leah Cohen", "href" => "essay" },
                  { "kicker" => "From the editor", "title" => "What we will not cover, and why", "body" => "A short letter on restraint as a kindness to readers.", "byline" => "By Ruth Ellison", "href" => "essay" },
                  { "kicker" => "City", "title" => "The last bookbinder on Printers Row", "byline" => "6 min read", "href" => "essay" },
                  { "kicker" => "Science", "title" => "Why the river runs warmer in March", "byline" => "8 min read", "href" => "essay" },
                  { "kicker" => "Culture", "title" => "A season of small theatres", "byline" => "5 min read", "href" => "essay" },
                  { "kicker" => "Letters", "title" => "Readers argue back", "byline" => "Weekly", "href" => "masthead" }
                ]
              }
            },
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "The long argument, printed once",
                "body" => "We publish a few pieces a week. Each one is edited until it can be read aloud. No slideshows. No “you won’t believe.”"
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "If it cannot survive a second read, it does not ship.",
                "attribution" => "Editor’s note"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Read the Sunday piece",
                "body" => "One essay. No account required to start.",
                "button_label" => "Open the essay",
                "button_href" => "essay"
              }
            }
          ]
        },
        {
          "title" => "Essay",
          "slug" => "essay",
          "home" => false,
          "nav_visible" => true,
          "role" => "essay",
          "layout_key" => "gazette_essay",
          "sections" => [
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "A sentence you can stand next to",
                "body" => "Replace this with the piece. Keep the paragraphs short enough to breathe, and long enough to earn the next one.\n\nName the people. Name the place. Leave the moral until the reader has the facts."
              }
            },
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "The picture that belongs here",
                "body" => "One photograph. A caption in the heading, not a paragraph under the frame.",
                "image_side" => "left"
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "I did not come here to be summarized.",
                "attribution" => "Subject of the piece",
                "role" => "Harbor night shift"
              }
            }
          ]
        },
        {
          "title" => "Masthead",
          "slug" => "masthead",
          "home" => false,
          "nav_visible" => true,
          "role" => "masthead",
          "layout_key" => "gazette_masthead",
          "sections" => [
            {
              "type" => "team_grid",
              "props" => {
                "heading" => "Masthead",
                "people" => [
                  { "name" => "Ruth Ellison", "role" => "Editor", "bio" => "Cuts a paragraph and sends the writer a better one." },
                  { "name" => "Samir Aziz", "role" => "Reporter", "bio" => "Stays for the second interview." },
                  { "name" => "Leah Cohen", "role" => "Design", "bio" => "Type first. Photography only when it earns the column." }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Tips and letters",
                "address" => "200 Printers Row",
                "email" => "tips@example.com",
                "phone" => "+1 555 013 1900",
                "hours" => "The desk is staffed weekdays, 9:00–17:00"
              }
            }
          ]
        }
      ].freeze
    end
  end
end