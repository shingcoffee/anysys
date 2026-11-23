# frozen_string_literal: true

module Websites
  module Skeletons
    # TED register: a dark stage hero, speakers up front, a day-by-day
    # program, ticket tiers with what each includes, and the venue.
    module Summit
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "summit_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Summit 2027 · Vancouver · April 12–16",
                "headline" => "Ideas that won't sit still",
                "subhead" => "Five days, eighty speakers and eighteen minutes each to change how you see the world.",
                "primary_label" => "Get tickets",
                "primary_href" => "tickets",
                "secondary_label" => "See the program",
                "secondary_href" => "program",
                "tone" => "dark"
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "80", "label" => "speakers" },
                  { "value" => "5", "label" => "days on one stage" },
                  { "value" => "1,800", "label" => "attendees from 70 countries" },
                  { "value" => "40M", "label" => "talk views last year" }
                ]
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "kicker" => "Speakers",
                "heading" => "On the red circle this year",
                "people" => [
                  { "name" => "Dr. Maya Chen", "role" => "Neuroscientist", "bio" => "On why boredom might be the most productive thing you do all week." },
                  { "name" => "Tomás Alvarez", "role" => "Architect", "bio" => "Building cities that cool themselves." },
                  { "name" => "Priya Raman", "role" => "Climate economist", "bio" => "The price of carbon, explained in one chart." },
                  { "name" => "Jonah Brooks", "role" => "Deep-sea explorer", "bio" => "Eleven kilometres down, and what lives there." }
                ]
              }
            },
            {
              "type" => "story_index",
              "props" => {
                "kicker" => "Watch",
                "heading" => "Most-watched talks",
                "stories" => [
                  { "kicker" => "Science · 18 min", "title" => "The surprising science of paying attention", "body" => "A neuroscientist's case for doing one thing at a time — and the experiment that convinced her.", "byline" => "Dr. Maya Chen", "href" => "https://example.com/talks/attention" },
                  { "kicker" => "Design · 14 min", "title" => "What a termite mound knows about air conditioning", "byline" => "Tomás Alvarez", "href" => "https://example.com/talks/termites" },
                  { "kicker" => "Climate · 12 min", "title" => "One chart that explains the energy transition", "byline" => "Priya Raman", "href" => "https://example.com/talks/energy" },
                  { "kicker" => "Ocean", "title" => "Life at the bottom of the trench", "byline" => "Jonah Brooks", "href" => "https://example.com/talks/trench" },
                  { "kicker" => "Society", "title" => "How to disagree without leaving the table", "byline" => "Ayo Adeyemi", "href" => "https://example.com/talks/disagree" },
                  { "kicker" => "Health", "title" => "The loneliness epidemic is curable", "byline" => "Dr. Sara Lind", "href" => "https://example.com/talks/loneliness" },
                  { "kicker" => "Technology", "title" => "Teaching machines to say “I don't know”", "byline" => "Kenji Mori", "href" => "https://example.com/talks/uncertainty" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Be in the room",
                "body" => "Tickets are released in three waves. Standard passes for this year's summit are almost gone.",
                "button_label" => "Get tickets",
                "button_href" => "tickets"
              }
            }
          ]
        },
        {
          "title" => "Program",
          "slug" => "program",
          "home" => false,
          "nav_visible" => true,
          "role" => "program",
          "layout_key" => "summit_program",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "Program",
                "headline" => "Twelve sessions. No panels, no slides full of bullet points.",
                "body" => "Every talk is eighteen minutes or less. Between sessions: long lunches, workshops and conversations you will still be having on the flight home."
              }
            },
            {
              "type" => "agenda",
              "props" => {
                "kicker" => "Day one · Monday, April 12",
                "heading" => "Beginnings",
                "sessions" => [
                  { "time" => "09:00", "title" => "Opening session: What we got wrong", "speaker" => "Hosted by Ayo Adeyemi", "body" => "Six speakers revisit an idea they once championed — and changed their minds about.", "track" => "Main stage" },
                  { "time" => "11:15", "title" => "The surprising science of paying attention", "speaker" => "Dr. Maya Chen", "track" => "Main stage" },
                  { "time" => "13:00", "title" => "Long lunch", "body" => "Tables are mixed by the program team. You will not sit with anyone you came with.", "track" => "Terrace" },
                  { "time" => "15:00", "title" => "Workshop: Telling a story in eighteen minutes", "speaker" => "The speaker coaching team", "track" => "Studio" },
                  { "time" => "19:30", "title" => "Opening night", "body" => "Dinner and live music on the harbour.", "track" => "Harbour hall" }
                ]
              }
            },
            {
              "type" => "agenda",
              "props" => {
                "kicker" => "Day two · Tuesday, April 13",
                "heading" => "Systems",
                "sessions" => [
                  { "time" => "09:00", "title" => "Cities that cool themselves", "speaker" => "Tomás Alvarez", "track" => "Main stage" },
                  { "time" => "10:30", "title" => "One chart that explains the energy transition", "speaker" => "Priya Raman", "track" => "Main stage" },
                  { "time" => "14:00", "title" => "Field trip: The seawall", "body" => "Walk the city's new flood defences with the engineers who built them.", "track" => "Offsite" },
                  { "time" => "17:00", "title" => "Life at the bottom of the trench", "speaker" => "Jonah Brooks", "track" => "Main stage" }
                ]
              }
            }
          ]
        },
        {
          "title" => "Tickets",
          "slug" => "tickets",
          "home" => false,
          "nav_visible" => true,
          "role" => "tickets",
          "layout_key" => "summit_tickets",
          "sections" => [
            {
              "type" => "pricing",
              "props" => {
                "kicker" => "Tickets",
                "heading" => "Choose how you attend",
                "subhead" => "All passes include every talk on the main stage. Prices in US dollars.",
                "tiers" => [
                  { "name" => "Livestream", "price" => "$299", "cadence" => "online", "body" => "Every session live, in high definition, wherever you are.", "features" => "All main-stage talks live\nReplays for 30 days\nOnline discussion rooms", "button_label" => "Stream it", "button_href" => "https://example.com/tickets/stream" },
                  { "name" => "Standard", "price" => "$6,500", "cadence" => "in person", "body" => "Five days in Vancouver with the full community.", "features" => "All sessions and workshops\nDaily lunches and opening night\nSpeaker meet-ups", "button_label" => "Apply to attend", "button_href" => "https://example.com/tickets/standard", "highlight" => "featured" },
                  { "name" => "Patron", "price" => "$25,000", "cadence" => "in person", "body" => "Reserved seating and time with speakers.", "features" => "Everything in Standard\nReserved seating\nPrivate speaker dinners", "button_label" => "Become a patron", "button_href" => "https://example.com/tickets/patron" }
                ]
              }
            },
            {
              "type" => "comparison_table",
              "props" => {
                "kicker" => "Compare passes",
                "heading" => "What each pass includes",
                "column_1" => "Livestream",
                "column_2" => "Standard",
                "column_3" => "Patron",
                "rows" => [
                  { "title" => "Main-stage talks", "value_1" => "✓", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Replays", "value_1" => "30 days", "value_2" => "1 year", "value_3" => "1 year" },
                  { "title" => "Workshops and field trips", "value_1" => "—", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Lunches and opening night", "value_1" => "—", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Reserved seating", "value_1" => "—", "value_2" => "—", "value_3" => "✓" },
                  { "title" => "Private speaker dinners", "value_1" => "—", "value_2" => "—", "value_3" => "✓" }
                ]
              }
            },
            {
              "type" => "faq",
              "props" => {
                "kicker" => "Questions",
                "heading" => "Before you apply",
                "items" => [
                  { "question" => "Why do in-person passes need an application?", "answer" => "We balance every audience by field, country and age. Most applications are answered within two weeks." },
                  { "question" => "Can I transfer my pass?", "answer" => "Yes, to anyone who is approved by the program team, up to thirty days before the summit." },
                  { "question" => "Are there scholarships?", "answer" => "Around ten percent of seats are funded for educators, researchers and nonprofit leaders." }
                ]
              }
            }
          ]
        },
        {
          "title" => "Venue",
          "slug" => "venue",
          "home" => false,
          "nav_visible" => true,
          "role" => "venue",
          "layout_key" => "summit_venue",
          "sections" => [
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "A theatre built on the water",
                "body" => "The Harbour Convention Centre seats 1,800 in a single, steeply raked hall — no seat more than thirty metres from the stage. The foyers open straight onto the seawall.",
                "image_side" => "right"
              }
            },
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Getting there",
                "heading" => "Venue and partner hotels",
                "subhead" => "Summit rates are held until March 1. Every hotel is within a ten-minute walk.",
                "places" => [
                  { "name" => "Harbour Convention Centre", "address" => "1055 Canada Place\nVancouver, BC", "hours" => "Doors open 08:00 daily", "phone" => "+1 604 555 0190", "button_label" => "Get directions", "button_href" => "https://example.com/map" },
                  { "name" => "The Pier Hotel", "address" => "900 Canada Place\nVancouver, BC", "hours" => "Summit rate from $389", "phone" => "+1 604 555 0142", "button_label" => "Book a room", "button_href" => "https://example.com/hotels/pier" },
                  { "name" => "Coal Harbour Suites", "address" => "1128 West Hastings Street\nVancouver, BC", "hours" => "Summit rate from $319", "phone" => "+1 604 555 0167", "button_label" => "Book a room", "button_href" => "https://example.com/hotels/coal-harbour" }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Talk to the attendee team",
                "address" => "1055 Canada Place\nVancouver, BC",
                "email" => "hello@example.com",
                "phone" => "+1 604 555 0100",
                "hours" => "Monday–Friday, 9:00–17:00 PT"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
