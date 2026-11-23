# frozen_string_literal: true

module Websites
  module Skeletons
    module Voyage
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "voyage_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "A sanctuary on the coast",
                "headline" => "Arrive, and the world goes quiet",
                "subhead" => "Forty pavilions above a private bay, a spa carved into the cliff and nowhere you need to be.",
                "primary_label" => "Check availability",
                "primary_href" => "stay",
                "secondary_label" => "Explore the resort",
                "secondary_href" => "experiences",
                "tone" => "dark"
              }
            },
            {
              "type" => "statement",
              "props" => {
                "kicker" => "The resort",
                "headline" => "Space, silence and a view that asks nothing of you.",
                "body" => "Designed by local craftsmen in stone and teak, every pavilion faces the sea. Staff outnumber guests three to one, and you will rarely notice them."
              }
            },
            {
              "type" => "gallery",
              "props" => {
                "heading" => "A day at the resort",
                "items" => [
                  { "caption" => "Morning on the terrace" },
                  { "caption" => "The infinity pool" },
                  { "caption" => "Pavilion bathing room" },
                  { "caption" => "Lunch under the frangipani" },
                  { "caption" => "The cliff spa" },
                  { "caption" => "Evening at the beach club" }
                ]
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "heading" => "From the guest book",
                "items" => [
                  { "quote" => "We came for four nights and changed our flights to stay ten.", "name" => "Charlotte & James", "role" => "London" },
                  { "quote" => "The most restful place I have ever been. The staff remembered everything.", "name" => "Mei Lin", "role" => "Singapore" },
                  { "quote" => "Every detail was considered, and none of it was loud.", "name" => "Alessandro R.", "role" => "Milan" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Your pavilion is waiting",
                "body" => "Book direct for complimentary airport transfers and a sunset sail.",
                "button_label" => "Reserve your stay",
                "button_href" => "stay"
              }
            }
          ]
        },
        {
          "title" => "Stay",
          "slug" => "stay",
          "home" => false,
          "nav_visible" => true,
          "role" => "stay",
          "layout_key" => "voyage_stay",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Accommodation",
                "headline" => "Pavilions and villas",
                "subhead" => "Each with a private terrace, deep soaking tub and uninterrupted sea view.",
                "primary_label" => "Enquire",
                "primary_href" => "contact"
              }
            },
            {
              "type" => "price_list",
              "props" => {
                "kicker" => "Rates",
                "heading" => "Stays and seasons",
                "subhead" => "Nightly rates, including breakfast and transfers.",
                "items" => [
                  { "title" => "Ocean pavilion", "body" => "90 m², king bed, terrace with daybed.", "price" => "from $1,200" },
                  { "title" => "Cliff pavilion", "body" => "120 m², private plunge pool.", "price" => "from $1,650" },
                  { "title" => "Two-bedroom villa", "body" => "280 m², pool, kitchen and dedicated host.", "price" => "from $3,900" },
                  { "title" => "The Residence", "body" => "Five bedrooms, private beach access, chef and staff.", "price" => "on request" }
                ]
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "heading" => "Inside the pavilions",
                "cells" => [
                  { "span" => "hero", "title" => "Built for stillness", "body" => "Hand-laid stone, local teak and linen woven on the island." },
                  { "span" => "unit", "title" => "Bathing rooms", "body" => "Open to the garden, closed to the world." },
                  { "span" => "unit", "title" => "Private terraces", "body" => "Breakfast arrives when you do." }
                ]
              }
            }
          ]
        },
        {
          "title" => "Experiences",
          "slug" => "experiences",
          "home" => false,
          "nav_visible" => true,
          "role" => "experiences",
          "layout_key" => "voyage_experiences",
          "sections" => [
            {
              "type" => "alternating_features",
              "props" => {
                "kicker" => "Experiences",
                "heading" => "Slow days, well spent",
                "items" => [
                  { "title" => "The cliff spa", "body" => "Treatments drawn from island traditions, in rooms cut into the rock." },
                  { "title" => "Sail at sunset", "body" => "A traditional boat, a small crew and the bay to yourselves." },
                  { "title" => "Dine anywhere", "body" => "The beach, the garden or your terrace. The menu follows the morning catch." }
                ]
              }
            },
            {
              "type" => "steps",
              "props" => {
                "heading" => "Planning your stay",
                "items" => [
                  { "title" => "Tell us your dates", "body" => "Our reservations team replies within the day." },
                  { "title" => "Shape your days", "body" => "A personal host plans experiences before you arrive." },
                  { "title" => "Arrive", "body" => "We meet you at the airport. The rest is taken care of." }
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
          "layout_key" => "voyage_contact",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Reservations",
                "address" => "Jalan Pantai Selatan\nUluwatu, Bali",
                "email" => "reservations@example.com",
                "phone" => "+62 361 555 0188",
                "hours" => "Our team is available around the clock"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
