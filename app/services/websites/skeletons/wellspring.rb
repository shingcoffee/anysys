# frozen_string_literal: true

module Websites
  module Skeletons
    # charity: water register: an emotional photo hero, the 100% promise,
    # field stories, a founding timeline, proof of impact and monthly giving.
    module Wellspring
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "wellspring_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "703 million people still walk for water",
                "headline" => "Clean water changes everything",
                "subhead" => "Health, school, work, time. It all starts with a tap within reach of home.",
                "primary_label" => "Give monthly",
                "primary_href" => "give",
                "secondary_label" => "See the proof",
                "secondary_href" => "impact",
                "tone" => "dark"
              }
            },
            {
              "type" => "statement",
              "props" => {
                "kicker" => "The 100% model",
                "headline" => "Every dollar you give reaches the field. Private donors cover our running costs.",
                "body" => "Two bank accounts, audited every year. One funds wells, rainwater tanks and filters. The other — paid for by a small group of founding supporters — keeps the lights on."
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "18.4M", "label" => "people with clean water" },
                  { "value" => "131k", "label" => "projects funded" },
                  { "value" => "29", "label" => "countries" },
                  { "value" => "100%", "label" => "of public gifts to the field" }
                ]
              }
            },
            {
              "type" => "story_index",
              "props" => {
                "kicker" => "From the field",
                "heading" => "Stories",
                "stories" => [
                  { "kicker" => "Ethiopia", "title" => "The morning Helen stopped carrying water", "body" => "For eleven years she walked four hours a day. Now the well is two minutes from her door — and she has started a business with the time.", "byline" => "8 min read", "href" => "impact" },
                  { "kicker" => "Malawi", "title" => "A school where the girls came back", "body" => "Attendance rose by a third once the latrines and the tap arrived.", "byline" => "5 min read", "href" => "impact" },
                  { "kicker" => "Nepal", "title" => "Gravity, pipe and a village committee", "body" => "How a spring six kilometres uphill now serves four hundred homes.", "byline" => "6 min read", "href" => "impact" },
                  { "kicker" => "Report", "title" => "What ten years of sensors taught us", "byline" => "Annual review", "href" => "impact" },
                  { "kicker" => "Partners", "title" => "Meet the drilling crews", "byline" => "Photo essay", "href" => "impact" },
                  { "kicker" => "Giving", "title" => "Why monthly gifts go further", "byline" => "3 min read", "href" => "give" },
                  { "kicker" => "Birthdays", "title" => "Pledge your birthday for water", "byline" => "Campaigns", "href" => "give" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Join The Spring",
                "body" => "A monthly gift that funds a new project every year — with photos and GPS coordinates when it is finished.",
                "button_label" => "Give monthly",
                "button_href" => "give"
              }
            }
          ]
        },
        {
          "title" => "Our story",
          "slug" => "story",
          "home" => false,
          "nav_visible" => true,
          "role" => "story",
          "layout_key" => "wellspring_story",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Our story",
                "headline" => "It started with one well and a birthday",
                "subhead" => "Our founder asked friends for twenty dollars instead of presents. Two hundred people said yes, and a village in northern Uganda got its first protected well.",
                "primary_label" => "Give monthly",
                "primary_href" => "give",
                "secondary_label" => "See our impact",
                "secondary_href" => "impact"
              }
            },
            {
              "type" => "timeline",
              "props" => {
                "kicker" => "Since 2008",
                "heading" => "Fifteen years, one idea",
                "subhead" => "Fund local partners, prove every project, and never spend a public dollar on overhead.",
                "items" => [
                  { "date" => "2008", "title" => "A birthday becomes a well", "body" => "Two hundred friends give $20 each. The first project opens in Lira, Uganda." },
                  { "date" => "2011", "title" => "The 100% model", "body" => "We split our finances in two, so public gifts only ever fund water." },
                  { "date" => "2015", "title" => "Photos and GPS for every project", "body" => "Donors start receiving the coordinates of the project they funded." },
                  { "date" => "2019", "title" => "Remote sensors", "body" => "Pumps report their flow every hour, so repairs happen in days, not months." },
                  { "date" => "2023", "title" => "Ten million people", "body" => "Our partners pass ten million people served across twenty-nine countries." }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "We are not here to build wells. We are here to make sure the water still flows in twenty years.",
                "attribution" => "Amara Okafor",
                "role" => "Director of programs"
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "kicker" => "Team",
                "heading" => "The people behind the pumps",
                "people" => [
                  { "name" => "Daniel Reyes", "role" => "Founder", "bio" => "Still answers the first email of every new monthly giver." },
                  { "name" => "Amara Okafor", "role" => "Programs", "bio" => "Works alongside partners in eleven countries." },
                  { "name" => "Lena Fischer", "role" => "Finance", "bio" => "Keeps the two bank accounts honest." },
                  { "name" => "Samuel Mensah", "role" => "Field technology", "bio" => "Built the sensor network that watches every pump." }
                ]
              }
            }
          ]
        },
        {
          "title" => "Impact",
          "slug" => "impact",
          "home" => false,
          "nav_visible" => true,
          "role" => "impact",
          "layout_key" => "wellspring_impact",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "Proof",
                "headline" => "Every project is photographed, mapped and reported back to the people who paid for it.",
                "body" => "Open data, independent audits and a sensor on every pump we can reach."
              }
            },
            {
              "type" => "steps",
              "props" => {
                "kicker" => "How it works",
                "heading" => "From your gift to a working tap",
                "items" => [
                  { "title" => "You give", "body" => "Your gift is pooled with others heading to the same region and sent in full to a local partner." },
                  { "title" => "Local partners build", "body" => "Community-led teams choose the right solution and train a water committee to run it." },
                  { "title" => "We prove it", "body" => "Within eighteen months you receive photos, GPS coordinates and the number of people served." }
                ]
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "kicker" => "Solutions",
                "heading" => "The right system for each place",
                "cells" => [
                  { "span" => "hero", "title" => "Drilled wells", "body" => "Deep boreholes with hand pumps or solar pumps, for communities above a reliable aquifer." },
                  { "span" => "wide", "title" => "Piped systems", "body" => "Gravity-fed springs and solar pumping that bring taps into the village." },
                  { "span" => "unit", "title" => "Rainwater catchment", "body" => "Roofs and tanks for schools and clinics." },
                  { "span" => "unit", "title" => "Sanitation", "body" => "Latrines and handwashing that keep water clean." }
                ]
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "92%", "label" => "of monitored pumps flowing today" },
                  { "value" => "4 days", "label" => "average repair time" },
                  { "value" => "1,200", "label" => "trained water committees" },
                  { "value" => "A+", "label" => "independent charity rating" }
                ]
              }
            }
          ]
        },
        {
          "title" => "Give",
          "slug" => "give",
          "home" => false,
          "nav_visible" => true,
          "role" => "give",
          "layout_key" => "wellspring_give",
          "sections" => [
            {
              "type" => "pricing",
              "props" => {
                "kicker" => "The Spring",
                "heading" => "Give monthly, see it land",
                "subhead" => "Cancel or change your gift at any time. Every gift is tax-deductible.",
                "tiers" => [
                  { "name" => "Drop", "price" => "$10", "cadence" => "per month", "body" => "Clean water for one person, every year.", "features" => "Project photos and GPS\nA yearly impact report", "button_label" => "Give $10", "button_href" => "https://example.com/give?amount=10" },
                  { "name" => "Stream", "price" => "$30", "cadence" => "per month", "body" => "Our most common gift — a family served each year.", "features" => "Project photos and GPS\nQuarterly field updates\nLive sensor data", "button_label" => "Give $30", "button_href" => "https://example.com/give?amount=30", "highlight" => "featured" },
                  { "name" => "River", "price" => "$100", "cadence" => "per month", "body" => "Funds a share of a school or clinic system.", "features" => "Everything in Stream\nA named project\nAn annual call with the field team", "button_label" => "Give $100", "button_href" => "https://example.com/give?amount=100" }
                ]
              }
            },
            {
              "type" => "faq",
              "props" => {
                "kicker" => "Questions",
                "heading" => "Before you give",
                "items" => [
                  { "question" => "Does all of my gift really go to water?", "answer" => "Yes. A separate group of private donors funds salaries, offices and fundraising, and both accounts are audited every year." },
                  { "question" => "When will I see my project?", "answer" => "Projects take twelve to eighteen months. We email photos and coordinates the week they are finished." },
                  { "question" => "Can I give once instead?", "answer" => "Of course. One-time gifts are pooled into the next project in the region with the greatest need." },
                  { "question" => "Is my gift tax-deductible?", "answer" => "We are a registered charity, and you will receive a receipt for every gift." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Pledge your birthday",
                "body" => "Ask friends to give instead of gifts. We will show them exactly where the water flows.",
                "button_label" => "Start a campaign",
                "button_href" => "https://example.com/campaign"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
