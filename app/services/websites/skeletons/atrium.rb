# frozen_string_literal: true

module Websites
  module Skeletons
    # MoMA register: bold display type, the current exhibition up front,
    # what is on view today, admission and hours, and membership.
    module Atrium
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "atrium_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Exhibition · Through January 18",
                "headline" => "Colour Field: Painting After 1950",
                "subhead" => "Seventy canvases, twelve painters and the decade abstraction learned to breathe.",
                "primary_label" => "Get tickets",
                "primary_href" => "visit",
                "secondary_label" => "What's on",
                "secondary_href" => "exhibitions",
                "tone" => "dark"
              }
            },
            {
              "type" => "story_index",
              "props" => {
                "kicker" => "Now on view",
                "heading" => "Exhibitions",
                "stories" => [
                  { "kicker" => "Floor 6 · Through January 18", "title" => "Colour Field: Painting After 1950", "body" => "The largest survey of the movement in forty years, with loans from thirty collections.", "byline" => "Special exhibition", "href" => "exhibitions" },
                  { "kicker" => "Floor 3 · Ongoing", "title" => "Chairs: A Century of Sitting", "byline" => "Architecture and design", "href" => "exhibitions" },
                  { "kicker" => "Floor 2 · Through March 2", "title" => "New Photography 2026", "byline" => "Photography", "href" => "exhibitions" },
                  { "kicker" => "Floor 4", "title" => "The Collection: 1940s–1970s", "byline" => "Painting and sculpture", "href" => "exhibitions" },
                  { "kicker" => "Floor 1", "title" => "Sound Room: Listening Out Loud", "byline" => "Media and performance", "href" => "exhibitions" },
                  { "kicker" => "Garden", "title" => "Sculpture after dark", "byline" => "Fridays until 21:00", "href" => "exhibitions" },
                  { "kicker" => "Theater", "title" => "Film series: The long take", "byline" => "Screenings nightly", "href" => "exhibitions" }
                ]
              }
            },
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "Members see it first",
                "body" => "Free admission all year, early hours before the galleries open, and previews of every new exhibition — plus guest passes to bring a friend.",
                "image_side" => "right"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Plan your visit",
                "body" => "Open daily from 10:30. Book a timed ticket online and skip the line at the door.",
                "button_label" => "Hours and admission",
                "button_href" => "visit"
              }
            }
          ]
        },
        {
          "title" => "Exhibitions",
          "slug" => "exhibitions",
          "home" => false,
          "nav_visible" => true,
          "role" => "exhibitions",
          "layout_key" => "atrium_exhibitions",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "Exhibitions and events",
                "headline" => "Six floors, one garden, two theatres — and something new every week."
              }
            },
            {
              "type" => "card_grid",
              "props" => {
                "kicker" => "Coming soon",
                "heading" => "Opening this season",
                "cards" => [
                  { "title" => "Paper Architecture", "body" => "Unbuilt buildings, drawn in pencil and ink. Opens February 14.", "href" => "https://example.com/exhibitions/paper-architecture" },
                  { "title" => "The Modern Kitchen", "body" => "How design changed the most-used room in the house. Opens March 8.", "href" => "https://example.com/exhibitions/modern-kitchen" },
                  { "title" => "Emerging Artists 2027", "body" => "Twenty artists showing in a museum for the first time. Opens April 2.", "href" => "https://example.com/exhibitions/emerging" }
                ]
              }
            },
            {
              "type" => "agenda",
              "props" => {
                "kicker" => "Today",
                "heading" => "Talks, tours and films",
                "subhead" => "Free with admission unless noted. Seating is first come, first served.",
                "sessions" => [
                  { "time" => "11:00", "title" => "Gallery tour: Colour Field", "speaker" => "Led by a curator", "track" => "Floor 6" },
                  { "time" => "13:30", "title" => "Drawing in the galleries", "body" => "Pencils and paper provided. All levels welcome.", "track" => "Floor 4" },
                  { "time" => "16:00", "title" => "Artist talk: Working large", "speaker" => "Nadia Osei in conversation", "track" => "Theater 1" },
                  { "time" => "19:00", "title" => "Film: The long take", "body" => "Tickets $12, members free.", "track" => "Theater 2" }
                ]
              }
            }
          ]
        },
        {
          "title" => "Visit",
          "slug" => "visit",
          "home" => false,
          "nav_visible" => true,
          "role" => "visit",
          "layout_key" => "atrium_visit",
          "sections" => [
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Visit",
                "heading" => "Two buildings, one ticket",
                "subhead" => "Your admission covers both sites on the same day.",
                "places" => [
                  { "name" => "The Museum", "address" => "11 West 53rd Street\nNew York, NY", "hours" => "Daily 10:30–17:30\nFridays until 21:00", "phone" => "+1 212 555 0180", "button_label" => "Get directions", "button_href" => "https://example.com/visit/museum" },
                  { "name" => "The Annex", "address" => "22-25 Jackson Avenue\nQueens, NY", "hours" => "Thursday–Monday 12:00–18:00", "phone" => "+1 718 555 0184", "button_label" => "Get directions", "button_href" => "https://example.com/visit/annex" }
                ]
              }
            },
            {
              "type" => "price_list",
              "props" => {
                "kicker" => "Admission",
                "heading" => "Tickets",
                "subhead" => "Timed tickets are released two weeks ahead.",
                "items" => [
                  { "title" => "Adults", "price" => "$30" },
                  { "title" => "Seniors", "body" => "65 and over, with ID", "price" => "$22" },
                  { "title" => "Students", "body" => "Full-time, with ID", "price" => "$17" },
                  { "title" => "Members", "price" => "Free" },
                  { "title" => "Children 16 and under", "price" => "Free" }
                ]
              }
            },
            {
              "type" => "faq",
              "props" => {
                "kicker" => "Good to know",
                "heading" => "Before you come",
                "items" => [
                  { "question" => "Can I bring a bag?", "answer" => "Bags larger than 11 × 14 inches are checked for free in the lobby." },
                  { "question" => "Is the museum accessible?", "answer" => "Every floor is step-free, wheelchairs are available at the entrance, and service animals are welcome." },
                  { "question" => "Can I take photographs?", "answer" => "Yes, for personal use and without flash — unless a sign in the gallery says otherwise." }
                ]
              }
            }
          ]
        },
        {
          "title" => "Membership",
          "slug" => "membership",
          "home" => false,
          "nav_visible" => true,
          "role" => "membership",
          "layout_key" => "atrium_membership",
          "sections" => [
            {
              "type" => "pricing",
              "props" => {
                "kicker" => "Membership",
                "heading" => "Come back as often as you like",
                "subhead" => "Membership pays for itself in three visits, and supports everything we do.",
                "tiers" => [
                  { "name" => "Individual", "price" => "$110", "cadence" => "per year", "body" => "Unlimited free admission for one.", "features" => "Free admission all year\nMember previews\n10% off in the store", "button_label" => "Join", "button_href" => "https://example.com/join/individual" },
                  { "name" => "Dual", "price" => "$180", "cadence" => "per year", "body" => "For you and a guest, every time.", "features" => "Everything in Individual\nA guest on every visit\nFour guest passes", "button_label" => "Join", "button_href" => "https://example.com/join/dual", "highlight" => "featured" },
                  { "name" => "Patron", "price" => "$1,000", "cadence" => "per year", "body" => "Behind the scenes with the curators.", "features" => "Everything in Dual\nCurator-led tours\nExhibition opening parties", "button_label" => "Join", "button_href" => "https://example.com/join/patron" }
                ]
              }
            },
            {
              "type" => "comparison_table",
              "props" => {
                "kicker" => "Benefits",
                "heading" => "Compare memberships",
                "column_1" => "Individual",
                "column_2" => "Dual",
                "column_3" => "Patron",
                "rows" => [
                  { "title" => "Free admission", "value_1" => "✓", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Guests per visit", "value_1" => "—", "value_2" => "1", "value_3" => "2" },
                  { "title" => "Member previews", "value_1" => "✓", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Store discount", "value_1" => "10%", "value_2" => "10%", "value_3" => "20%" },
                  { "title" => "Curator-led tours", "value_1" => "—", "value_2" => "—", "value_3" => "✓" },
                  { "title" => "Opening parties", "value_1" => "—", "value_2" => "—", "value_3" => "✓" }
                ]
              }
            }
          ]
        }
      ].freeze
    end
  end
end
