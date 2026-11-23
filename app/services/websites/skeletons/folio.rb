# frozen_string_literal: true

module Websites
  module Skeletons
    module Folio
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "folio_home",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "Independent design studio",
                "headline" => "We make identities, books, buildings and brands that people remember.",
                "body" => "Founded by designers who wanted to stay designers. Every project is led by a partner who does the work, not just the pitch."
              }
            },
            {
              "type" => "gallery",
              "props" => {
                "kicker" => "Selected work",
                "heading" => "Recent projects",
                "items" => [
                  { "caption" => "City Museum — identity and wayfinding" },
                  { "caption" => "Northwind — annual report" },
                  { "caption" => "Opera House — season campaign" },
                  { "caption" => "Field Journal — editorial design" },
                  { "caption" => "Harbour Library — signage" },
                  { "caption" => "Atlas — type family" },
                  { "caption" => "Kiln — packaging" }
                ]
              }
            },
            {
              "type" => "logo_cloud",
              "props" => {
                "heading" => "Some of the people we have worked with",
                "items" => [
                  { "name" => "City Museum" },
                  { "name" => "Northwind" },
                  { "name" => "The Opera" },
                  { "name" => "Atlas" },
                  { "name" => "Kiln" },
                  { "name" => "Harbour" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Have a project in mind?",
                "body" => "We take on a small number of new commissions each season.",
                "button_label" => "Start a conversation",
                "button_href" => "contact"
              }
            }
          ]
        },
        {
          "title" => "Work",
          "slug" => "work",
          "home" => false,
          "nav_visible" => true,
          "role" => "work",
          "layout_key" => "folio_work",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Case study",
                "headline" => "A museum that finally looks like its collection",
                "tone" => "light",
                "subhead" => "Identity, signage and digital for a two-hundred-year-old institution."
              }
            },
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "The brief",
                "body" => "The museum had grown by accretion: six buildings, four logos and a website nobody could navigate.\n\nWe proposed one idea — the frame — and let it do the work. Every sign, poster and page now holds the art the same way a gallery wall does."
              }
            },
            {
              "type" => "gallery",
              "props" => {
                "heading" => "Outcomes",
                "items" => [
                  { "caption" => "Main entrance" },
                  { "caption" => "Exhibition posters" },
                  { "caption" => "Wayfinding system" },
                  { "caption" => "Members' guide" }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => { "quote" => "They did not redesign the museum. They showed us what it already was.", "attribution" => "Director, City Museum" }
            }
          ]
        },
        {
          "title" => "Studio",
          "slug" => "studio",
          "home" => false,
          "nav_visible" => true,
          "role" => "studio",
          "layout_key" => "folio_studio",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "Studio",
                "headline" => "Twenty-three partners. One shared table.",
                "body" => "We are organised as a collective of independent practices who share a studio, a reputation and a lot of lunches."
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "kicker" => "Partners",
                "heading" => "Who leads the work",
                "people" => [
                  { "name" => "Harriet Cole", "role" => "Partner, identity", "bio" => "Has designed marks for three national institutions." },
                  { "name" => "Omar Haddad", "role" => "Partner, architecture", "bio" => "Builds signage systems that people never notice." },
                  { "name" => "Yuki Tanaka", "role" => "Partner, editorial", "bio" => "Believes every book should be read, not just admired." },
                  { "name" => "Felix Brandt", "role" => "Partner, digital", "bio" => "Makes interfaces as calm as print." }
                ]
              }
            },
            {
              "type" => "feature_grid",
              "props" => {
                "kicker" => "Services",
                "heading" => "What we do",
                "items" => [
                  { "title" => "Identity", "body" => "Names, marks and systems built to last decades." },
                  { "title" => "Editorial", "body" => "Books, magazines and reports with a point of view." },
                  { "title" => "Environments", "body" => "Signage, exhibitions and wayfinding." }
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
          "layout_key" => "folio_contact",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Come and see the studio",
                "address" => "11 Needham Road\nLondon W11",
                "email" => "studio@example.com",
                "phone" => "+44 20 7555 0100",
                "hours" => "Monday–Friday, 9:30–18:00"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
