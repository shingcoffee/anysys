# frozen_string_literal: true

module Websites
  module Skeletons
    # Monocle register: a print-magazine editorial — serif, correspondents,
    # city briefings, and a shop that still sells the issue.
    module Quarterly
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "quarterly_home",
          "sections" => [
            {
              "type" => "announcement",
              "props" => {
                "badge" => "Issue 48",
                "body" => "The Quality of Life survey — twenty-five cities, one argument about the afternoon.",
                "link_label" => "Read the briefing",
                "href" => "stories",
                "surface" => "accent"
              }
            },
            {
              "type" => "statement",
              "props" => {
                "kicker" => "Quarterly",
                "headline" => "A magazine for people who still go outside.",
                "body" => "Cities, shops, a decent lunch, and the policy that makes all three possible. Printed on paper that lasts the month, and a site that does not shout."
              }
            },
            {
              "type" => "story_index",
              "props" => {
                "kicker" => "In this issue",
                "heading" => "The briefing",
                "stories" => [
                  { "kicker" => "Cover", "title" => "Where the afternoon still works", "body" => "Twenty-five cities ranked not by glass, but by a bench, a tram, and a place that will serve you at four.", "byline" => "T. Adler · 18 min", "href" => "stories" },
                  { "kicker" => "Dispatch", "title" => "A bakery in Lisbon that refused a second shift", "byline" => "I. Costa · 9 min", "href" => "stories" },
                  { "kicker" => "Design", "title" => "The lamp that has been in production since 1974", "byline" => "K. Mori · 7 min", "href" => "stories" },
                  { "kicker" => "Business", "title" => "Why the family hotel is buying the block", "byline" => "Briefing", "href" => "stories" },
                  { "kicker" => "Food", "title" => "One counter, twelve seats, no booking", "byline" => "Lunch", "href" => "stories" },
                  { "kicker" => "Culture", "title" => "A radio station that still signs off at midnight", "byline" => "Essay", "href" => "stories" },
                  { "kicker" => "The shop", "title" => "Issue 48, the tote, the map", "byline" => "Now shipping", "href" => "https://example.com/shop" }
                ]
              }
            },
            {
              "type" => "collection_rail",
              "props" => {
                "kicker" => "Correspondents",
                "heading" => "From the bureaux",
                "subhead" => "People who live there, writing as if you might visit on Thursday.",
                "aspect" => "landscape",
                "items" => [
                  { "title" => "Tokyo", "meta" => "K. Mori", "href" => "stories" },
                  { "title" => "Lisbon", "meta" => "I. Costa", "href" => "stories" },
                  { "title" => "Copenhagen", "meta" => "L. Berg", "href" => "stories" },
                  { "title" => "Mexico City", "meta" => "S. Reyes", "href" => "stories" },
                  { "title" => "Melbourne", "meta" => "J. Hart", "href" => "stories" },
                  { "title" => "Zurich", "meta" => "A. Keller", "href" => "stories" }
                ],
                "align" => "start",
                "surface" => "muted"
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "A city is working when you can walk to lunch, sit down without a reservation, and still make the 14:10.",
                "attribution" => "Tilda Adler",
                "role" => "Editor, Issue 48",
                "surface" => "muted"
              }
            },
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "Printed first. The site is the afternoon edition.",
                "body" => "The issue closes on a Tuesday. Subscribers have it on the Friday. What you read here is the same piece, set for a smaller page — not a feed, not a teaser.",
                "image_side" => "left"
              }
            },
            {
              "type" => "cta_split",
              "props" => {
                "kicker" => "Subscribe",
                "headline" => "Ten issues, a summer special, and the Quality of Life book",
                "body" => "£90 a year, posted. The site comes with it. Gift a year and we will write the card.",
                "primary_label" => "Take a subscription",
                "primary_href" => "https://example.com/subscribe",
                "secondary_label" => "Visit the shop",
                "secondary_href" => "contact",
                "image_side" => "right"
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
          "layout_key" => "quarterly_stories",
          "sections" => [
            {
              "type" => "story_index",
              "props" => {
                "kicker" => "The archive",
                "heading" => "Recent dispatches",
                "stories" => [
                  { "kicker" => "Issue 48", "title" => "Where the afternoon still works", "body" => "The Quality of Life survey, argued rather than scored.", "byline" => "Cover", "href" => "stories" },
                  { "kicker" => "Lisbon", "title" => "The bakery that kept one shift", "byline" => "I. Costa", "href" => "stories" },
                  { "kicker" => "Tokyo", "title" => "A department-store basement at 11:00", "byline" => "K. Mori", "href" => "stories" },
                  { "kicker" => "Zurich", "title" => "The tram that still has a conductor", "byline" => "A. Keller", "href" => "stories" },
                  { "kicker" => "Design", "title" => "In production since 1974", "byline" => "Object", "href" => "stories" },
                  { "kicker" => "Hotels", "title" => "Family houses that bought the neighbours", "byline" => "Briefing", "href" => "stories" },
                  { "kicker" => "Radio", "title" => "Signing off at midnight, on purpose", "byline" => "Essay", "href" => "stories" },
                  { "kicker" => "Issue 47", "title" => "The retail issue", "byline" => "Archive", "href" => "stories" }
                ]
              }
            },
            {
              "type" => "gallery",
              "props" => {
                "kicker" => "From the issue",
                "heading" => "Pictures that earned their page",
                "items" => [
                  { "caption" => "Lisbon, 16:10" },
                  { "caption" => "The 1974 lamp" },
                  { "caption" => "A Zurich tram" },
                  { "caption" => "Tokyo basement" },
                  { "caption" => "Issue 48, on the table" }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "How we report",
                "body" => "Correspondents live in the city they cover. We do not fly in for a caption. If a shop is recommended, someone on staff has paid. If a number is published, a second person has checked it.\n\nCorrections run on the same page, in the next issue, and here. We do not bury them."
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "Write as if the reader might go. If they cannot, write so they can smell the room anyway.",
                "attribution" => "House style",
                "role" => "Posted in every bureau",
                "surface" => "muted"
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
          "layout_key" => "quarterly_about",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "The magazine",
                "headline" => "Independent, printed, and still curious about lunch.",
                "body" => "Quarterly is owned by the people who edit it. We take advertising we would run as a story. We decline the rest."
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "kicker" => "Masthead",
                "heading" => "Who closes the issue",
                "people" => [
                  { "name" => "Tilda Adler", "role" => "Editor", "bio" => "Argues for the afternoon. Has never missed a close." },
                  { "name" => "Kenji Mori", "role" => "Tokyo / design", "bio" => "Objects, shops, the quiet luxury of something that still works." },
                  { "name" => "Ines Costa", "role" => "Lisbon / food", "bio" => "Counters, bakeries, the politics of a second shift." },
                  { "name" => "Arun Keller", "role" => "Zurich / cities", "bio" => "Trams, housing, why a bench is a policy." }
                ],
                "align" => "start",
                "surface" => "muted"
              }
            },
            {
              "type" => "timeline",
              "props" => {
                "kicker" => "The house",
                "heading" => "From a newsletter to a newsstand",
                "items" => [
                  { "date" => "2007", "title" => "A weekly letter", "body" => "Cities, shops, a recommendation that could be used on Thursday." },
                  { "date" => "2011", "title" => "The first issue", "body" => "Eighty pages, a map, and a refusal to put the cover behind a celebrity." },
                  { "date" => "2016", "title" => "Bureaux", "body" => "Tokyo, Lisbon, then the rest. Correspondents, not stringers." },
                  { "date" => "2024", "title" => "Still independent", "body" => "We turned down a sale. The staff bought the rest of the shares." }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Editorial and subscriptions",
                "address" => "12 Midori House\nLondon W1",
                "email" => "desk@example.com",
                "phone" => "+44 20 7555 0110",
                "hours" => "Tuesday–Friday, 10:00–18:00"
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
          "layout_key" => "quarterly_contact",
          "sections" => [
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Bureaux and the shop",
                "heading" => "Visit, or write to the desk",
                "subhead" => "The London shop holds the issue, the maps, and a coffee we will not over-describe.",
                "places" => [
                  { "name" => "London shop", "address" => "12 Midori House\nLondon W1", "hours" => "Tuesday–Saturday 10:00–19:00", "phone" => "+44 20 7555 0110", "button_label" => "Get directions", "button_href" => "https://example.com/map" },
                  { "name" => "Tokyo bureau", "address" => "3-2 Jingumae\nShibuya, Tokyo", "hours" => "Weekdays 11:00–18:00", "phone" => "+81 3 5551 0100", "button_label" => "Get directions", "button_href" => "https://example.com/map" },
                  { "name" => "Lisbon bureau", "address" => "18 Rua Garrett\nLisbon", "hours" => "Wednesday–Saturday 11:00–19:00", "phone" => "+351 21 555 0144", "button_label" => "Get directions", "button_href" => "https://example.com/map" }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Subscriptions, advertising, corrections",
                "address" => "12 Midori House\nLondon W1",
                "email" => "desk@example.com",
                "phone" => "+44 20 7555 0110",
                "hours" => "Tuesday–Friday, 10:00–18:00"
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "Before you write",
                "items" => [
                  { "question" => "Can I buy a single issue?", "answer" => "Yes — in the London shop, at selected newsstands, or posted from the site. Back issues from 2018 are in print." },
                  { "question" => "Do you take pitches?", "answer" => "Correspondents are staff. We rarely buy a piece. If you have a correction, write immediately." },
                  { "question" => "Is the site behind a paywall?", "answer" => "The cover and two pieces are open. The rest comes with a subscription, as the paper does." }
                ],
                "surface" => "muted"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
