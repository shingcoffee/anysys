# frozen_string_literal: true

module Websites
  module Skeletons
    module Lumen
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "lumen_home",
          "sections" => [
            {
              "type" => "hero_centered",
              "props" => {
                "eyebrow" => "Introducing Lumen 3",
                "headline" => "Ship the web at the speed of thought",
                "subhead" => "Preview every change, deploy on push, and scale to the edge without touching a server.",
                "primary_label" => "Start deploying",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "Read the docs",
                "secondary_href" => "platform"
              }
            },
            {
              "type" => "logo_cloud",
              "props" => {
                "heading" => "Trusted by the teams behind the fastest sites on the internet",
                "items" => [
                  { "name" => "Northwind" },
                  { "name" => "Halcyon" },
                  { "name" => "Vertex" },
                  { "name" => "Oakline" },
                  { "name" => "Parallel" },
                  { "name" => "Monolith" }
                ]
              }
            },
            {
              "type" => "feature_grid",
              "props" => {
                "kicker" => "Platform",
                "heading" => "Everything between a commit and a customer",
                "subhead" => "One workflow from local branch to global edge. No tickets, no tribal knowledge.",
                "items" => [
                  { "title" => "Preview every branch", "body" => "Each pull request gets a live URL. Designers, editors and QA review the real thing, not a screenshot." },
                  { "title" => "Deploy on push", "body" => "Merge to main and the site is live in seconds. Roll back just as fast when the numbers disagree." },
                  { "title" => "Edge by default", "body" => "Pages render in the region nearest your visitor. Latency stops being a roadmap item." },
                  { "title" => "Observability built in", "body" => "Real user metrics, logs and traces arrive with the deploy that caused them." },
                  { "title" => "Secure from the start", "body" => "Automatic TLS, DDoS mitigation and a firewall you configure in plain language." },
                  { "title" => "Priced like software", "body" => "Pay for what you serve. No reserved capacity, no surprise egress bills." }
                ]
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "kicker" => "Workflow",
                "heading" => "Built for the way modern teams collaborate",
                "cells" => [
                  { "span" => "hero", "title" => "Comments on the live page", "body" => "Leave feedback directly on the preview. Threads resolve when the fix ships." },
                  { "span" => "unit", "title" => "Instant rollbacks", "body" => "Every deploy is immutable. Promote any previous build in one click." },
                  { "span" => "unit", "title" => "Feature flags", "body" => "Launch to one percent, then everyone, from the same dashboard." },
                  { "span" => "wide", "title" => "Analytics without the tag soup", "body" => "Privacy-friendly traffic and Core Web Vitals, no third-party scripts required." }
                ]
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "kicker" => "Customers",
                "heading" => "Loved by engineers. Approved by finance.",
                "items" => [
                  { "quote" => "We went from weekly releases to forty deploys a day, and our on-call rotation got quieter.", "name" => "Maya Chen", "role" => "Head of Platform, Halcyon" },
                  { "quote" => "Preview links changed how our designers work. Review happens on the real product now.", "name" => "Daniel Osei", "role" => "Design Lead, Vertex" },
                  { "quote" => "Our largest launch of the year was also our most boring deploy. That is the highest compliment.", "name" => "Sara Lindqvist", "role" => "CTO, Oakline" },
                  { "quote" => "Time to first byte dropped by half the week we migrated. Nobody touched the code.", "name" => "Tom Alvarez", "role" => "Staff Engineer, Parallel" },
                  { "quote" => "The bill finally tracks our traffic instead of our fears.", "name" => "Priya Raman", "role" => "VP Engineering, Monolith" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Your next deploy could be live in a minute",
                "body" => "Connect a repository and ship your first preview before the coffee cools.",
                "button_label" => "Start for free",
                "button_href" => "https://example.com/start"
              }
            }
          ]
        },
        {
          "title" => "Platform",
          "slug" => "platform",
          "home" => false,
          "nav_visible" => true,
          "role" => "platform",
          "layout_key" => "lumen_platform",
          "sections" => [
            {
              "type" => "hero_centered",
              "props" => {
                "eyebrow" => "Platform",
                "headline" => "Infrastructure that disappears",
                "subhead" => "Framework-aware builds, a global edge network, and a workflow your whole team can use.",
                "primary_label" => "Talk to sales",
                "primary_href" => "contact"
              }
            },
            {
              "type" => "steps",
              "props" => {
                "kicker" => "How it works",
                "heading" => "From git push to global in three steps",
                "items" => [
                  { "title" => "Connect your repository", "body" => "Import from any git provider. We detect the framework and configure the build." },
                  { "title" => "Review on a preview URL", "body" => "Every branch deploys to its own address with comments, checks and metrics attached." },
                  { "title" => "Merge to go live", "body" => "Production updates atomically across every region. Nothing to babysit." }
                ]
              }
            },
            {
              "type" => "alternating_features",
              "props" => {
                "kicker" => "Deep dive",
                "heading" => "Details that add up",
                "items" => [
                  { "title" => "Builds that remember", "body" => "Incremental caching reuses unchanged work, so a one-line fix does not rebuild the world." },
                  { "title" => "Functions where your users are", "body" => "Run server logic at the edge with the same code you write locally. Cold starts measured in milliseconds." },
                  { "title" => "Guardrails, not gates", "body" => "Required checks, protected branches and audit logs keep velocity and compliance on speaking terms." }
                ]
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "35ms", "label" => "median global TTFB" },
                  { "value" => "99.99%", "label" => "edge availability" },
                  { "value" => "120+", "label" => "points of presence" },
                  { "value" => "4.2B", "label" => "requests a week" }
                ]
              }
            }
          ]
        },
        {
          "title" => "Pricing",
          "slug" => "pricing",
          "home" => false,
          "nav_visible" => true,
          "role" => "pricing",
          "layout_key" => "lumen_pricing",
          "sections" => [
            {
              "type" => "pricing",
              "props" => {
                "kicker" => "Pricing",
                "heading" => "Start free. Scale when it matters.",
                "subhead" => "Transparent plans for hobby projects, growing teams and global enterprises.",
                "tiers" => [
                  {
                    "name" => "Hobby",
                    "price" => "$0",
                    "cadence" => "forever",
                    "body" => "For personal projects and experiments.",
                    "features" => "Unlimited previews\nAutomatic TLS\nCommunity support",
                    "button_label" => "Start free",
                    "button_href" => "https://example.com/start",
                    "highlight" => "standard"
                  },
                  {
                    "name" => "Pro",
                    "price" => "$20",
                    "cadence" => "per member / month",
                    "body" => "For teams shipping production sites.",
                    "features" => "Everything in Hobby\nTeam comments on previews\nAdvanced analytics\nEmail support",
                    "button_label" => "Start a trial",
                    "button_href" => "https://example.com/start",
                    "highlight" => "featured"
                  },
                  {
                    "name" => "Enterprise",
                    "price" => "Custom",
                    "cadence" => "annual",
                    "body" => "For organisations with scale and compliance needs.",
                    "features" => "Everything in Pro\nSSO and SCIM\n99.99% SLA\nDedicated success engineer",
                    "button_label" => "Contact sales",
                    "button_href" => "contact",
                    "highlight" => "standard"
                  }
                ]
              }
            },
            {
              "type" => "faq",
              "props" => {
                "kicker" => "FAQ",
                "heading" => "Pricing questions",
                "items" => [
                  { "question" => "What counts as a member?", "answer" => "Anyone who can deploy or change settings. Reviewers who only comment on previews are free." },
                  { "question" => "Can I change plans later?", "answer" => "Yes, at any time. Upgrades are prorated and downgrades apply at the next cycle." },
                  { "question" => "Do you offer discounts for startups and nonprofits?", "answer" => "We do. Write to us with a little about your project and we will set you up." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Not sure which plan fits?",
                "body" => "Tell us about your traffic and team. We will recommend the smallest plan that works.",
                "button_label" => "Talk to us",
                "button_href" => "contact"
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
          "layout_key" => "lumen_contact",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Talk to an engineer, not a script",
                "address" => "500 Howard Street\nSan Francisco, CA",
                "email" => "hello@example.com",
                "phone" => "+1 415 555 0142",
                "hours" => "Support around the clock\nSales Monday–Friday, 9:00–18:00 PT"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
