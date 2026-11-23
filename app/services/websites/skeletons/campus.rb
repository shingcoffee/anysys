# frozen_string_literal: true

module Websites
  module Skeletons
    # University register: scale, programs, people, and a visit.
    module Campus
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "campus_home",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Admissions",
                "headline" => "A place to do the serious work",
                "subhead" => "Research, teaching, and a city that does not end at the gate.",
                "primary_label" => "Explore programs",
                "primary_href" => "programs",
                "secondary_label" => "Plan a visit",
                "secondary_href" => "visit"
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "label" => "Students", "value" => "16,400" },
                  { "label" => "Faculty", "value" => "2,100" },
                  { "label" => "Countries", "value" => "90" },
                  { "label" => "Programs", "value" => "180" }
                ]
              }
            },
            {
              "type" => "card_grid",
              "props" => {
                "heading" => "Where to begin",
                "subhead" => "Three doors. Each one opens onto a different kind of work.",
                "cards" => [
                  { "title" => "Undergraduate", "body" => "A broad first year, then a major you choose with evidence.", "href" => "programs" },
                  { "title" => "Graduate", "body" => "Labs, studios, and advisors who still publish.", "href" => "programs" },
                  { "title" => "Public programs", "body" => "Lectures and exhibitions open to the city.", "href" => "visit" }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "Come for the library. Stay because someone argued with you kindly.",
                "attribution" => "Dean of Students"
              }
            },
            {
              "type" => "steps",
              "props" => {
                "kicker" => "Admissions",
                "heading" => "Applying in three steps",
                "items" => [
                  { "title" => "Visit", "body" => "Tour the campus, sit in on a class and meet current students." },
                  { "title" => "Apply", "body" => "Submit one application online. Fee waivers are available." },
                  { "title" => "Decide", "body" => "Decisions arrive in spring with a full financial aid offer." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "The next term starts in September",
                "body" => "Applications are open. A conversation with admissions is free.",
                "button_label" => "Start an application",
                "button_href" => "https://example.com/apply"
              }
            }
          ]
        },
        {
          "title" => "Programs",
          "slug" => "programs",
          "home" => false,
          "nav_visible" => true,
          "role" => "programs",
          "layout_key" => "campus_programs",
          "sections" => [
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "Study that has a room of its own",
                "body" => "Each program publishes what you will actually do in the first year: courses, a studio or a lab, and the person who reads your work."
              }
            },
            {
              "type" => "card_grid",
              "props" => {
                "heading" => "Schools",
                "cards" => [
                  { "title" => "Arts and sciences", "body" => "Letters, numbers, and the argument between them.", "href" => "people" },
                  { "title" => "Engineering", "body" => "Make the thing, then measure it.", "href" => "people" },
                  { "title" => "Design", "body" => "Studios with daylight and a critique that starts on time.", "href" => "people" }
                ]
              }
            }
          ]
        },
        {
          "title" => "People",
          "slug" => "people",
          "home" => false,
          "nav_visible" => true,
          "role" => "people",
          "layout_key" => "campus_people",
          "sections" => [
            {
              "type" => "team_grid",
              "props" => {
                "heading" => "Faculty you can find",
                "people" => [
                  { "name" => "Dr. Helen Cho", "role" => "History", "bio" => "Writes about cities and the people who keep them." },
                  { "name" => "Prof. Malik Owens", "role" => "Engineering", "bio" => "Runs a lab that ships instruments, not just papers." },
                  { "name" => "Ada Voss", "role" => "Design", "bio" => "Teaches type, then makes students throw the first draft away." }
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
          "layout_key" => "campus_visit",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Come to campus",
                "address" => "1 College Walk\nAdmissions Hall",
                "email" => "visit@example.edu",
                "phone" => "+1 555 016 8800",
                "hours" => "Tours weekdays at 10:00 and 14:00"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Reserve a tour",
                "body" => "Ninety minutes. A student guide. The library if it is open.",
                "button_label" => "Book a tour",
                "button_href" => "https://example.com/visit"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
