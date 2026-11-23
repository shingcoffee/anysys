# frozen_string_literal: true

module Websites
  module Skeletons
    module Terrain
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "terrain_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Autumn collection",
                "headline" => "Built for the long way round",
                "subhead" => "Repairable gear for people who would rather be outside, made to last longer than the trip.",
                "primary_label" => "Shop the collection",
                "primary_href" => "gear",
                "secondary_label" => "Our mission",
                "secondary_href" => "mission",
                "tone" => "dark"
              }
            },
            {
              "type" => "statement",
              "props" => {
                "kicker" => "Our reason",
                "headline" => "We are in business to protect the places we love to explore.",
                "body" => "Every jacket is designed to be repaired, not replaced. One percent of every sale funds grassroots groups defending wild land and water."
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "kicker" => "Field tested",
                "heading" => "Gear for every kind of weather",
                "cells" => [
                  { "span" => "hero", "title" => "Alpine shell", "body" => "Three-layer recycled nylon, taped seams, a hood that fits over a helmet." },
                  { "span" => "unit", "title" => "Down, responsibly", "body" => "Traceable, certified and warm when wet." },
                  { "span" => "unit", "title" => "Base layers", "body" => "Merino that breathes on the climb and dries at camp." },
                  { "span" => "wide", "title" => "Packs that carry the weight", "body" => "Frames that move with you, fabric that shrugs off granite." }
                ]
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "1%", "label" => "of sales to the planet" },
                  { "value" => "87k", "label" => "repairs last year" },
                  { "value" => "100%", "label" => "renewable-powered studios" },
                  { "value" => "40", "label" => "years in the field" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Worn wear, still going",
                "body" => "Trade in the gear you have outgrown. We repair it, clean it and send it back into the world.",
                "button_label" => "Trade in",
                "button_href" => "mission"
              }
            }
          ]
        },
        {
          "title" => "Gear",
          "slug" => "gear",
          "home" => false,
          "nav_visible" => true,
          "role" => "gear",
          "layout_key" => "terrain_gear",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Gear",
                "headline" => "Fewer things, made better",
                "subhead" => "A small line of essentials we design, test and repair ourselves.",
                "primary_label" => "Find a store",
                "primary_href" => "contact"
              }
            },
            {
              "type" => "card_grid",
              "props" => {
                "kicker" => "Collections",
                "heading" => "Choose your terrain",
                "cards" => [
                  { "title" => "Alpine", "body" => "Shells, insulation and packs for high, cold and committing days.", "href" => "contact" },
                  { "title" => "Trail", "body" => "Light layers for long miles and fast weather.", "href" => "contact" },
                  { "title" => "Water", "body" => "Wetsuits and boardshorts for cold swells and warm ones.", "href" => "contact" }
                ]
              }
            },
            {
              "type" => "feature_grid",
              "props" => {
                "kicker" => "Materials",
                "heading" => "What goes into every piece",
                "items" => [
                  { "title" => "Recycled fabrics", "body" => "Most of our line is made from recycled nylon and polyester." },
                  { "title" => "Fair Trade sewing", "body" => "Premiums paid directly to the people who make our clothes." },
                  { "title" => "Lifetime repairs", "body" => "If it breaks, send it back. We will fix it for as long as it can be fixed." }
                ]
              }
            }
          ]
        },
        {
          "title" => "Mission",
          "slug" => "mission",
          "home" => false,
          "nav_visible" => true,
          "role" => "mission",
          "layout_key" => "terrain_mission",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Mission",
                "headline" => "The planet is our only shareholder",
                "subhead" => "Profit that is not reinvested in the business goes to fighting the environmental crisis.",
                "tone" => "dark"
              }
            },
            {
              "type" => "alternating_features",
              "props" => {
                "kicker" => "Activism",
                "heading" => "Where the money goes",
                "items" => [
                  { "title" => "Keep wild rivers wild", "body" => "We fund legal teams and local groups challenging dams on the last free-flowing rivers." },
                  { "title" => "Regenerative farming", "body" => "Our cotton comes from farms rebuilding soil rather than depleting it." },
                  { "title" => "Public lands, protected", "body" => "Grants and campaigns to keep the backcountry open to everyone, and closed to extraction." }
                ]
              }
            },
            {
              "type" => "timeline",
              "props" => {
                "kicker" => "Our history",
                "heading" => "Fifty years in the field",
                "items" => [
                  { "date" => "1973", "title" => "A tin shed in Ventura", "body" => "Climbing hardware, forged by hand, sold out of the back of a car." },
                  { "date" => "1985", "title" => "One percent for the planet", "body" => "We start giving one percent of sales to grassroots environmental groups." },
                  { "date" => "1996", "title" => "Organic cotton, all of it", "body" => "Every cotton garment switches to organic in a single season." },
                  { "date" => "2013", "title" => "Worn Wear", "body" => "A repair and resale programme, because the greenest jacket is the one you already own." },
                  { "date" => "2022", "title" => "The planet as shareholder", "body" => "Ownership moves to a trust and a nonprofit, so profits fund the fight." }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => { "quote" => "The more you know, the less you need.", "attribution" => "A climbing maxim we try to live by" }
            }
          ]
        },
        {
          "title" => "Contact",
          "slug" => "contact",
          "home" => false,
          "nav_visible" => true,
          "role" => "contact",
          "layout_key" => "terrain_contact",
          "sections" => [
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Stores",
                "heading" => "Stores and repair shops",
                "subhead" => "Bring anything we made, however old. If we can fix it, we will.",
                "places" => [
                  { "name" => "Ventura", "address" => "259 West Santa Clara Street\nVentura, California", "hours" => "Daily 10:00–18:00\nRepairs on site", "phone" => "+1 805 555 0110", "button_label" => "Get directions", "button_href" => "https://example.com/stores/ventura" },
                  { "name" => "Boulder", "address" => "1630 Pearl Street\nBoulder, Colorado", "hours" => "Daily 10:00–19:00", "phone" => "+1 303 555 0132", "button_label" => "Get directions", "button_href" => "https://example.com/stores/boulder" },
                  { "name" => "Chamonix", "address" => "12 Rue du Docteur Paccard\nChamonix, France", "hours" => "Daily 9:30–19:30", "phone" => "+33 4 55 55 01 90", "button_label" => "Get directions", "button_href" => "https://example.com/stores/chamonix" }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Visit the repair shop",
                "address" => "259 West Santa Clara Street\nVentura, California",
                "email" => "repairs@example.com",
                "phone" => "+1 805 555 0110",
                "hours" => "Every day, 10:00–18:00"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
