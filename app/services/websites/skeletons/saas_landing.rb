# frozen_string_literal: true

module Websites
  module Skeletons
    module SaasLanding
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
                "eyebrow" => "Now in general availability",
                "headline" => "The operating system for teams that ship",
                "subhead" => "One workspace for plans, reviews, and the work itself — calm enough for Monday, fast enough for launch week.",
                "primary_label" => "Start building",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "See how it works",
                "secondary_href" => "about"
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "12k", "label" => "product teams" },
                  { "value" => "98%", "label" => "uptime this year" },
                  { "value" => "40", "label" => "countries" },
                  { "value" => "4.9", "label" => "avg. review" }
                ]
              }
            },
            {
              "type" => "logo_cloud",
              "props" => {
                "heading" => "Chosen by product teams at",
                "items" => [
                  { "name" => "Northwind" },
                  { "name" => "Halcyon" },
                  { "name" => "Vertex" },
                  { "name" => "Oakline" },
                  { "name" => "Parallel" }
                ]
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "heading" => "Everything in one pass",
                "cells" => [
                  { "span" => "hero", "title" => "A timeline that tells the truth", "body" => "Dates, owners, and the actual diff — not a slide that was green last Thursday." },
                  { "span" => "wide", "title" => "Reviews without the scavenger hunt", "body" => "Comments land on the work. Decisions stay next to the thing they changed." },
                  { "span" => "unit", "title" => "Spaces", "body" => "A home for each product. Permissions that match how you already staff." },
                  { "span" => "unit", "title" => "Pulse", "body" => "A Monday digest that fits in one screen. No dashboard tourism." }
                ]
              }
            },
            {
              "type" => "alternating_features",
              "props" => {
                "heading" => "Built for the week you actually have",
                "items" => [
                  {
                    "title" => "Plan in the same place you build",
                    "body" => "Roadmaps are documents, not decorations. Drag a date, and the rest of the system notices."
                  },
                  {
                    "title" => "Ship with a paper trail",
                    "body" => "Every release writes its own changelog. Support, sales, and the next hire can read what landed."
                  },
                  {
                    "title" => "Invite the room, not the company",
                    "body" => "Guests see the project. They never see the rest. Leave with the files, not a forwarding address."
                  }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "We stopped running status in three tools. The work is the status now.",
                "attribution" => "Priya Nandakumar",
                "role" => "VP Product, Northwind"
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "kicker" => "Customers",
                "heading" => "Teams that stopped chasing status",
                "items" => [
                  { "quote" => "Our Monday meeting went from an hour to fifteen minutes. The timeline already told everyone what changed.", "name" => "Lena Park", "role" => "Engineering Manager, Halcyon" },
                  { "quote" => "Reviews finally happen where the work is. Nobody asks for the link anymore.", "name" => "Omar Haddad", "role" => "Design Lead, Vertex" },
                  { "quote" => "We migrated four tools in a weekend and kept every ticket number.", "name" => "Julia Brandt", "role" => "Head of Ops, Oakline" }
                ]
              }
            },
            {
              "type" => "pricing",
              "props" => {
                "kicker" => "Pricing",
                "heading" => "Simple plans that grow with the team",
                "subhead" => "Every plan includes unlimited projects and guests.",
                "tiers" => [
                  { "name" => "Starter", "price" => "$0", "cadence" => "per seat / month", "body" => "For small teams finding their rhythm.", "features" => "Up to 10 seats\nTimelines and reviews\n7-day history", "button_label" => "Start free", "button_href" => "https://example.com/start", "highlight" => "standard" },
                  { "name" => "Team", "price" => "$12", "cadence" => "per seat / month", "body" => "For teams shipping every week.", "features" => "Unlimited seats\nChangelogs and pulse digests\nUnlimited history\nGuest access", "button_label" => "Start a trial", "button_href" => "https://example.com/start", "highlight" => "featured" },
                  { "name" => "Enterprise", "price" => "Custom", "cadence" => "annual billing", "body" => "For organisations with a security review.", "features" => "SSO and SCIM\nAudit log\nDedicated success manager", "button_label" => "Talk to sales", "button_href" => "contact", "highlight" => "standard" }
                ]
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "Questions we hear first",
                "items" => [
                  {
                    "question" => "Can we import the backlog we already have?",
                    "answer" => "Yes. CSV, API, or a guided migration. We keep identifiers so your links do not die."
                  },
                  {
                    "question" => "Does it replace our chat?",
                    "answer" => "No. It sits beside it. Decisions get written down here so chat can stay chat."
                  },
                  {
                    "question" => "How do you handle security reviews?",
                    "answer" => "SSO, SCIM, audit log, and a room that answers questionnaires without a six-week wait."
                  },
                  {
                    "question" => "What if we outgrow the first workspace?",
                    "answer" => "Add spaces, not instances. Billing follows seats. Data stays in one place."
                  }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Start with a single team",
                "body" => "Fourteen days. Your own data. No credit card until you decide to stay.",
                "button_label" => "Create a workspace",
                "button_href" => "https://example.com/start"
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
                "heading" => "Software should feel like a well-run studio",
                "body" => "We were tired of tools that made planning a performance and building an afterthought. So we made a workspace where the plan is the work, and the work is visible.\n\nThe company is small on purpose. Design and engineering sit in the same room. Support reads the changelog before it ships. We would rather do fewer things with a finished edge."
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "heading" => "Who you will hear from",
                "people" => [
                  { "name" => "Alex Chen", "role" => "Founder", "bio" => "Spent a decade on launch trains. Still writes the first-run copy." },
                  { "name" => "Noor Haddad", "role" => "Design", "bio" => "Protects empty space. The product is calmer because of it." },
                  { "name" => "Sam Okonkwo", "role" => "Engineering", "bio" => "Keeps the timeline honest. If it is green here, it is green in production." }
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
                "heading" => "Talk to a person",
                "address" => "Studio 4, Pier 12\nSan Francisco, CA",
                "email" => "hello@example.com",
                "phone" => "+1 555 019 4400",
                "hours" => "Monday–Friday, 9:00–18:00 Pacific"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
