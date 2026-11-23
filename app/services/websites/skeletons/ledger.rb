# frozen_string_literal: true

module Websites
  module Skeletons
    # Stripe register: trust numbers, a product grid, and a pricing page.
    module Ledger
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "ledger_home",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Payments",
                "headline" => "Financial infrastructure for the internet",
                "subhead" => "Accept payments, send payouts, and automate billing — one API, with the reliability a public company expects.",
                "primary_label" => "Start now",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "See pricing",
                "secondary_href" => "pricing"
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "label" => "Businesses", "value" => "Millions" },
                  { "label" => "Countries", "value" => "46" },
                  { "label" => "Uptime", "value" => "99.99%" },
                  { "label" => "Volume", "value" => "$1T+" }
                ]
              }
            },
            {
              "type" => "card_grid",
              "props" => {
                "heading" => "A complete stack",
                "subhead" => "Payments, billing, and identity — each product is enough on its own.",
                "cards" => [
                  { "title" => "Payments", "body" => "Cards, wallets, and bank debits with a single integration.", "href" => "about" },
                  { "title" => "Billing", "body" => "Subscriptions, usage, and invoices that reconcile themselves.", "href" => "pricing" },
                  { "title" => "Connect", "body" => "Pay out to sellers without becoming their bank.", "href" => "about" }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "We moved the whole checkout in a week. Finance stopped asking where the money was.",
                "attribution" => "Elena Cho",
                "role" => "CFO, Northwind"
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "Asked before the security review",
                "items" => [
                  { "question" => "Do you hold funds?", "answer" => "Licensed partners do. You see every cent in a ledger you can export." },
                  { "question" => "Can we keep our existing processor for a while?", "answer" => "Yes. Run both, then cut over one product at a time." },
                  { "question" => "How do refunds work?", "answer" => "Full or partial, from the dashboard or the API, with the original fee rules applied." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Start with a test key",
                "body" => "No contract to read a document. Production when you are ready.",
                "button_label" => "Create an account",
                "button_href" => "https://example.com/start"
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
          "layout_key" => "ledger_pricing",
          "sections" => [
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "Pricing that stays boring",
                "body" => "A published rate for cards. A published rate for payouts. Volume discounts are a conversation, not a maze."
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "label" => "Cards", "value" => "2.9% + 30¢" },
                  { "label" => "Payouts", "value" => "Included" },
                  { "label" => "Invoices", "value" => "0.4%" },
                  { "label" => "Setup", "value" => "Free" }
                ]
              }
            },
            {
              "type" => "pricing",
              "props" => {
                "kicker" => "Plans",
                "heading" => "Pick the plan that matches your volume",
                "tiers" => [
                  { "name" => "Standard", "price" => "2.9%", "cadence" => "+ 30¢ per charge", "body" => "Everything you need to start taking payments.", "features" => "Cards and wallets\nNext-day payouts\nHosted invoices", "button_label" => "Start now", "button_href" => "https://example.com/start", "highlight" => "standard" },
                  { "name" => "Scale", "price" => "2.5%", "cadence" => "+ 25¢ per charge", "body" => "For businesses processing over $1M a year.", "features" => "Everything in Standard\nRevenue reporting\nPriority support", "button_label" => "Talk to us", "button_href" => "contact", "highlight" => "featured" },
                  { "name" => "Custom", "price" => "Let's talk", "cadence" => "volume pricing", "body" => "Interchange-plus pricing for platforms.", "features" => "Dedicated account team\nCustom contracts\nMulti-entity support", "button_label" => "Contact sales", "button_href" => "contact", "highlight" => "standard" }
                ]
              }
            },
            {
              "type" => "comparison_table",
              "props" => {
                "kicker" => "Compare plans",
                "heading" => "Every feature, side by side",
                "column_1" => "Standard",
                "column_2" => "Scale",
                "column_3" => "Custom",
                "rows" => [
                  { "title" => "Cards and wallets", "value_1" => "✓", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Payouts", "value_1" => "Next day", "value_2" => "Same day", "value_3" => "Instant" },
                  { "title" => "Hosted invoices", "value_1" => "✓", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Revenue reporting", "value_1" => "—", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Multi-entity accounts", "value_1" => "—", "value_2" => "—", "value_3" => "✓" },
                  { "title" => "Support", "value_1" => "Email", "value_2" => "Priority", "value_3" => "Dedicated team" }
                ]
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "The fine print, in plain language",
                "items" => [
                  { "question" => "Are there monthly fees?", "answer" => "No platform fee on the standard plan. You pay when money moves." },
                  { "question" => "What about international cards?", "answer" => "A small cross-border add-on, shown before you charge." },
                  { "question" => "Can we get a custom rate?", "answer" => "Yes, once volume is real. We will not invent a number to win the meeting." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Estimate it with your own numbers",
                "body" => "Bring last quarter’s volume. We will price it in the room.",
                "button_label" => "Talk to sales",
                "button_href" => "contact"
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
          "layout_key" => "ledger_about",
          "sections" => [
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "Built for the people who move money",
                "body" => "Engineers, finance leads, and the founder who still checks the dashboard on Sunday. We write the docs as carefully as the code."
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "heading" => "Who you will meet",
                "people" => [
                  { "name" => "Amina Shah", "role" => "Engineering", "bio" => "Owns the API. Answers questions in the docs before they are asked." },
                  { "name" => "Chris Adler", "role" => "Finance", "bio" => "Former controller. Keeps the ledger explainable to an auditor." },
                  { "name" => "Noor Hassan", "role" => "Support", "bio" => "On the thread until the payment clears, not until the ticket closes." }
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
          "layout_key" => "ledger_contact",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Talk to us",
                "address" => "500 Market Street\nSan Francisco",
                "email" => "sales@example.com",
                "phone" => "+1 555 010 2400",
                "hours" => "Weekdays, 9:00–18:00 Pacific"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
