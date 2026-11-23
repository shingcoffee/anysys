# frozen_string_literal: true

module Websites
  module Skeletons
    module Monograph
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "monograph_home",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "Issue 14 — Slow Mornings",
                "headline" => "A quarterly about the small rituals that make a life feel like your own.",
                "body" => "Each issue follows one idea through homes, kitchens and studios on four continents. We print on uncoated paper, publish four times a year, and never run a listicle.\n\nThis season: the first hour of the day, and the people who guard it."
              }
            },
            {
              "type" => "gallery",
              "props" => {
                "kicker" => "In this issue",
                "heading" => "Rooms, tables and the light between them",
                "items" => [
                  { "caption" => "A kitchen in Kyoto, 7:10 a.m." },
                  { "caption" => "Linen drying in Lisbon" },
                  { "caption" => "The long table at Villa Soli" },
                  { "caption" => "Pour-over, no timer" },
                  { "caption" => "A reading chair in Copenhagen" },
                  { "caption" => "Morning bread, still warm" }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => { "quote" => "Slowness is not a lack of ambition. It is attention, applied on purpose.", "attribution" => "Ines Moreau", "role" => "Editor in chief" }
            },
            {
              "type" => "card_grid",
              "props" => {
                "kicker" => "Stories",
                "heading" => "Read the issue",
                "cards" => [
                  { "title" => "The architect who wakes at four", "body" => "Hiroshi Tanabe designs houses around a single window and a pot of tea.", "href" => "journal" },
                  { "title" => "A bakery with no sign", "body" => "In a Lisbon side street, the queue is the only advertisement.", "href" => "journal" },
                  { "title" => "Notes on unhurried hosting", "body" => "Six hosts on dinners that last longer than planned, on purpose.", "href" => "journal" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Four issues, delivered with the seasons",
                "body" => "Subscribe to the print edition and receive the archive essay collection free.",
                "button_label" => "Subscribe",
                "button_href" => "about"
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
          "layout_key" => "monograph_journal",
          "sections" => [
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "The first hour",
                "body" => "The alarm is optional. What matters is what happens after it: the kettle, the window, the decision not to reach for the phone.\n\nWe spent a year asking people how they begin the day. Not the productivity version — the real one, with its small superstitions and borrowed habits.\n\nWhat we found was less a routine than a posture. People who protect their mornings are not rigid. They are simply clear about what comes first."
              }
            },
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "Kyoto, early",
                "body" => "Hiroshi opens the shutters before anything else. The garden tells him the weather; the weather tells him the day.",
                "image_side" => "left"
              }
            },
            {
              "type" => "gallery",
              "props" => {
                "heading" => "Field notes",
                "items" => [
                  { "caption" => "Tea, first steep" },
                  { "caption" => "The study before anyone is up" },
                  { "caption" => "Market flowers, Saturday" }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => { "quote" => "I do not plan the morning. I just refuse to hurry it.", "attribution" => "Hiroshi Tanabe", "role" => "Architect" }
            }
          ]
        },
        {
          "title" => "About",
          "slug" => "about",
          "home" => false,
          "nav_visible" => true,
          "role" => "about",
          "layout_key" => "monograph_about",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "About",
                "headline" => "Made slowly, by a small team, for readers who finish things.",
                "body" => "We are an independent press of seven people based in Copenhagen. We commission photographers and writers we admire and give them time.\n\nNo advertising inside the issue. Ever."
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "kicker" => "Masthead",
                "heading" => "The people behind the pages",
                "people" => [
                  { "name" => "Ines Moreau", "role" => "Editor in chief", "bio" => "Former architecture critic. Reads everything twice." },
                  { "name" => "Kasper Holm", "role" => "Creative director", "bio" => "Sets type by hand when nobody is watching." },
                  { "name" => "Aiko Mori", "role" => "Photo editor", "bio" => "Believes most photographs are improved by waiting." },
                  { "name" => "Lena Vogel", "role" => "Managing editor", "bio" => "Keeps the calendar, the budget and the peace." }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Write to the editors",
                "address" => "Studiestræde 12\n1455 Copenhagen",
                "email" => "letters@example.com",
                "hours" => "We answer every letter within a month"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
