# frozen_string_literal: true

module Websites
  module Skeletons
    module Presence
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "presence_home",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Introduction",
                "headline" => "A place for the work that lasts",
                "subhead" => "We design programs, spaces, and stories for people who care about craft.",
                "primary_label" => "See our work",
                "primary_href" => "services",
                "secondary_label" => "About us",
                "secondary_href" => "about"
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "12", "label" => "years" },
                  { "value" => "40", "label" => "cities" },
                  { "value" => "180", "label" => "collaborators" },
                  { "value" => "4", "label" => "studios" }
                ]
              }
            },
            {
              "type" => "card_grid",
              "props" => {
                "heading" => "What we make",
                "subhead" => "Three practices, one standard: work you can return to.",
                "cards" => [
                  {
                    "title" => "Programs",
                    "body" => "Curricula, residencies, and seasonal series designed so people actually finish — and remember why they started.",
                    "href" => "services"
                  },
                  {
                    "title" => "Spaces",
                    "body" => "Galleries, rooms, and courtyards arranged for attention. Quiet enough to think. Open enough to gather.",
                    "href" => "services"
                  },
                  {
                    "title" => "Stories",
                    "body" => "Films, books, and field notes that carry a place to people who will never visit — and still feel they have.",
                    "href" => "about"
                  }
                ]
              }
            },
            {
              "type" => "steps",
              "props" => {
                "kicker" => "How we work",
                "heading" => "From first conversation to opening day",
                "items" => [
                  { "title" => "Listen", "body" => "We start with the people who will use the place, not the brief." },
                  { "title" => "Draw", "body" => "Sketches, models and walk-throughs until the idea holds its shape." },
                  { "title" => "Build", "body" => "We stay on site with the makers until the last detail is right." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Visit us",
                "body" => "The studio is open most weekdays. Come see the work on the walls, not just on the site.",
                "button_label" => "Visit us",
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
          "layout_key" => "presence_about",
          "sections" => [
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "A studio with a long memory",
                "body" => "We began as a small workshop above a bookshop. The work got larger. The standard did not. We still start on paper, still argue about type, still leave the room when the work is only almost right.",
                "image_side" => "left"
              }
            },
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "How we work",
                "body" => "Every engagement begins with a walk — through a neighborhood, a syllabus, or a half-finished draft. We listen longer than is fashionable.\n\nThen we make. Prototypes, not decks. Rooms you can stand in. Copy you can read out loud. We show the work early, while it can still change.\n\nWe stay until the thing can live without us: staff who know the ritual, a calendar that breathes, a sentence on the door that is true."
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "They treated our history as material, not costume. The building feels like itself, only more so.",
                "attribution" => "Elena Voss",
                "role" => "Director, Harbour Archive"
              }
            }
          ]
        },
        {
          "title" => "Services",
          "slug" => "services",
          "home" => false,
          "nav_visible" => true,
          "role" => "services",
          "layout_key" => "presence_services",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Services",
                "headline" => "Make the next decade feel considered",
                "subhead" => "From a single room to a city-wide season.",
                "tone" => "light"
              }
            },
            {
              "type" => "alternating_features",
              "props" => {
                "heading" => "A practice in three movements",
                "items" => [
                  {
                    "title" => "Commission a program",
                    "body" => "We design the arc: who it is for, what they make, how it ends. Then we staff it, print it, and open the doors."
                  },
                  {
                    "title" => "Shape a space",
                    "body" => "Furniture, light, and the sentence on the wall. Circulation that invites lingering without trapping anyone."
                  },
                  {
                    "title" => "Tell the work",
                    "body" => "A film, a book, a site that does not shout. Documentation that is itself a piece of the practice."
                  }
                ]
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "heading" => "On the boards now",
                "cells" => [
                  { "span" => "hero", "title" => "The River School", "body" => "A year-long making program along a working waterfront — boats, type, and supper." },
                  { "span" => "wide", "title" => "Reading rooms", "body" => "Four small libraries, each with one long table and no Wi-Fi." },
                  { "span" => "unit", "title" => "Field notes", "body" => "A seasonal press. Short runs. Cloth covers." },
                  { "span" => "unit", "title" => "Night studio", "body" => "Open hours for members who work after the city goes quiet." }
                ]
              }
            }
          ]
        },
        {
          "title" => "Team",
          "slug" => "team",
          "home" => false,
          "nav_visible" => true,
          "role" => "team",
          "layout_key" => "presence_team",
          "sections" => [
            {
              "type" => "team_grid",
              "props" => {
                "heading" => "The people in the room",
                "people" => [
                  { "name" => "Mara Ellison", "role" => "Principal", "bio" => "Trained as an architect. Keeps a notebook for every building we have ever loved." },
                  { "name" => "Jonah Park", "role" => "Programs", "bio" => "Builds calendars that people actually keep. Former teacher, current host." },
                  { "name" => "Sofia Rahman", "role" => "Editorial", "bio" => "Edits until the sentence can stand alone. Once typeset a book on a train." },
                  { "name" => "Leo Hart", "role" => "Studio", "bio" => "Light, joinery, and the last coat of paint. Says less than the rooms do." }
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
          "layout_key" => "presence_contact",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Come by",
                "address" => "14 Binder Lane\nThird floor\nThe harbour side of town",
                "email" => "hello@example.org",
                "phone" => "+1 555 014 2000",
                "hours" => "Tuesday–Friday, 11:00–18:00\nSaturdays by appointment"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Write first if you can",
                "body" => "A short note about the work you want to make is enough. We read everything.",
                "button_label" => "Meet the team",
                "button_href" => "team"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
