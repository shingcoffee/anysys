# frozen_string_literal: true

module Websites
  module Skeletons
    module Product
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "saas_home",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Linear-calm, Notion-clear",
                "headline" => "A workspace that stays out of the way",
                "subhead" => "Docs, issues, and the work itself in one quiet surface — built for teams who already know what they are doing.",
                "primary_label" => "See how it works",
                "primary_href" => "features",
                "secondary_label" => "About",
                "secondary_href" => "about"
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "12k", "label" => "teams" },
                  { "value" => "4.9", "label" => "care score" },
                  { "value" => "30ms", "label" => "keystroke" },
                  { "value" => "0", "label" => "feed" }
                ]
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "heading" => "One place for the work",
                "cells" => [
                  { "span" => "hero", "title" => "Pages that feel like paper", "body" => "Write. Indent. Done. No slash-menu tourism." },
                  { "span" => "wide", "title" => "Issues next to the spec", "body" => "The ticket lives beside the paragraph it came from." },
                  { "span" => "unit", "title" => "Fast", "body" => "Opens before you finish the thought." },
                  { "span" => "unit", "title" => "Quiet", "body" => "No badges begging for a click." }
                ]
              }
            },
            {
              "type" => "alternating_features",
              "props" => {
                "heading" => "What you actually do here",
                "items" => [
                  { "title" => "Write the spec once", "body" => "The page is the source. Comments stay on the sentence they change." },
                  { "title" => "Ship with a trail", "body" => "Every issue knows which paragraph it came from. Every launch has a date." },
                  { "title" => "Invite the room", "body" => "Guests see the work, not the company's entire archive." }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "We stopped running a second tool for docs. The spec is next to the issue. That was the whole product.",
                "attribution" => "Priya Shah",
                "role" => "Head of Product"
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "Questions teams actually ask",
                "items" => [
                  { "question" => "Is this a docs tool or a tracker?", "answer" => "Both, on purpose. The page is the spec; the issue is the work against it." },
                  { "question" => "Can we import from elsewhere?", "answer" => "Yes. Markdown in, structured pages out. We do not trap your writing." },
                  { "question" => "Do you have a feed?", "answer" => "No. You open the thing you are working on." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Start with one page",
                "body" => "If it is still the place you write six months later, it is working.",
                "button_label" => "Talk to us",
                "button_href" => "contact"
              }
            }
          ]
        },
        {
          "title" => "Features",
          "slug" => "features",
          "home" => false,
          "nav_visible" => true,
          "role" => "services",
          "layout_key" => "presence_services",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Product",
                "headline" => "Fewer surfaces. More finished work.",
                "subhead" => "Writing, tracking, and review without a dashboard for each.",
                "primary_label" => "Contact",
                "primary_href" => "contact",
                "tone" => "light"
              }
            },
            {
              "type" => "alternating_features",
              "props" => {
                "heading" => "Built for the week, not the demo",
                "items" => [
                  { "title" => "Editor", "body" => "Fast enough to think in. Keyboard first. Paste stays paste." },
                  { "title" => "Issues", "body" => "Small, dated, owned. Linked to the sentence they came from." },
                  { "title" => "Review", "body" => "Comments on the work. Decisions stay next to the change." }
                ]
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "heading" => "Details that compound",
                "cells" => [
                  { "span" => "hero", "title" => "Search that finds the paragraph", "body" => "Not a pile of filenames. The sentence you remember." },
                  { "span" => "wide", "title" => "Permissions that match the team", "body" => "A guest sees a page. Not the whole company." },
                  { "span" => "unit", "title" => "Export", "body" => "Markdown. Always." },
                  { "span" => "unit", "title" => "Offline", "body" => "The page you had open still opens." }
                ]
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
          "layout_key" => "saas_about",
          "sections" => [
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "A small team that uses the product",
                "body" => "We build the workspace we wished we had at previous companies: one place to write, one place to track, nothing in a feed. The company is the size of a serious studio — on purpose."
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "heading" => "Who is here",
                "people" => [
                  { "name" => "Mina Cole", "role" => "Design", "bio" => "Protects empty space. If a control needs a tour, it is wrong." },
                  { "name" => "Owen Park", "role" => "Engineering", "bio" => "Latency is a product decision. He treats it like one." },
                  { "name" => "Hana Yusuf", "role" => "Writing", "bio" => "The in-app copy is hers. So is the refusal to say 'delight'." }
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
          "layout_key" => "contact_simple",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "A human replies",
                "address" => "",
                "email" => "hello@example.com",
                "phone" => "",
                "hours" => "Weekdays."
              }
            }
          ]
        }
      ]
    end
  end
end
