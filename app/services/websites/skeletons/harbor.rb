# frozen_string_literal: true

module Websites
  module Skeletons
    # Shopify register: a commerce platform for merchants — first sale,
    # themes, checkout, and the shop that outgrows the dining table.
    module Harbor
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "harbor_home",
          "sections" => [
            {
              "type" => "announcement",
              "props" => {
                "badge" => "Summer",
                "body" => "Harbor Checkout 3 — one page, shopper wallets, and a thank-you that can sell the next thing.",
                "link_label" => "See checkout",
                "href" => "features",
                "surface" => "accent"
              }
            },
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "For merchants",
                "headline" => "The shop that starts tonight and still works at a million orders",
                "subhead" => "Pick a theme, add a product, take a payment. When the queue appears, the same admin still fits in one tab.",
                "primary_label" => "Start selling",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "See a live shop",
                "secondary_href" => "stories"
              }
            },
            {
              "type" => "metrics",
              "props" => {
                "kicker" => "Last quarter",
                "heading" => "What merchants actually did",
                "items" => [
                  { "value" => "$4.1B", "label" => "GMV on Harbor", "body" => "Paid out to shops in 38 currencies, most of them under ten people." },
                  { "value" => "3 min", "label" => "median time to first product", "body" => "From an empty store to something a friend can buy." },
                  { "value" => "1.8%", "label" => "checkout fee, card", "body" => "No surprise extras for wallets, local methods or a second currency." },
                  { "value" => "12k", "label" => "apps in the bench", "body" => "Subscriptions, wholesale, a loyalty card — installed, not rebuilt." }
                ],
                "align" => "center",
                "surface" => "muted"
              }
            },
            {
              "type" => "collection_rail",
              "props" => {
                "kicker" => "On Harbor this week",
                "heading" => "Shops that opened with one product",
                "subhead" => "A candle, a knife, a jacket. Then a second SKU, then a staff login.",
                "aspect" => "portrait",
                "items" => [
                  { "title" => "Kiln Goods", "meta" => "Ceramics · Portland", "href" => "stories" },
                  { "title" => "North Hem", "meta" => "Workwear · Montreal", "href" => "stories" },
                  { "title" => "Salt & Rind", "meta" => "Pantry · Lisbon", "href" => "stories" },
                  { "title" => "Paper Room", "meta" => "Stationery · Kyoto", "href" => "stories" },
                  { "title" => "Afterlight", "meta" => "Lamps · Brooklyn", "href" => "stories" },
                  { "title" => "Field Notes Co.", "meta" => "Journals · Chicago", "href" => "stories" },
                  { "title" => "Harbor House", "meta" => "Home · Melbourne", "href" => "stories" }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "feature_tabs",
              "props" => {
                "kicker" => "The platform",
                "heading" => "Everything between a listing and a loyal customer",
                "subhead" => "Online, in person, and the unglamorous middle — inventory, tax, a packing slip.",
                "tabs" => [
                  { "label" => "Storefront", "title" => "A theme you can edit without breaking Friday", "body" => "Sections, not templates. Change the hero, the rail, the footer — on a phone, if you have to." },
                  { "label" => "Checkout", "title" => "Shoppers finish. You keep the margin.", "body" => "Wallets, local methods, a one-page flow. Recovered carts land in the same inbox as new orders." },
                  { "label" => "Inventory", "title" => "One number for the site and the till", "body" => "Sell the last jacket online and the shop floor knows before someone walks it to the door." },
                  { "label" => "Apps", "title" => "Extend the shop without rebuilding it", "body" => "Subscriptions, wholesale, reviews, a loyalty stamp. Install, try, remove." }
                ],
                "align" => "start",
                "spacing" => "roomy"
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "kicker" => "Merchants",
                "heading" => "From the dining table to a second warehouse",
                "items" => [
                  { "quote" => "I listed the first candle at 11pm. Someone in Berlin bought it before I slept.", "name" => "Priya Raman", "role" => "Founder, Kiln Goods" },
                  { "quote" => "We added a second location without hiring a second ops person. The till and the site share a brain.", "name" => "Tom Alvarez", "role" => "Owner, North Hem" },
                  { "quote" => "Checkout used to be the thing I apologised for. Now it is the thing people mention.", "name" => "Ines Costa", "role" => "Salt & Rind" }
                ],
                "surface" => "muted",
                "align" => "center"
              }
            },
            {
              "type" => "cta_split",
              "props" => {
                "kicker" => "Fourteen days, no card",
                "headline" => "Open the shop. Sell the first thing.",
                "body" => "A theme, a product, a test payment. Keep the store if it feels like yours. We will not nag you with a banner.",
                "primary_label" => "Start selling",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "Compare plans",
                "secondary_href" => "pricing",
                "image_side" => "right"
              }
            }
          ]
        },
        {
          "title" => "Features",
          "slug" => "features",
          "home" => false,
          "nav_visible" => true,
          "role" => "features",
          "layout_key" => "harbor_features",
          "sections" => [
            {
              "type" => "product_spotlight",
              "props" => {
                "kicker" => "Harbor Checkout",
                "headline" => "A one-page finish that shoppers actually complete",
                "subhead" => "Address, method, place order. Shopper wallets, local rails and a thank-you that can hold a second offer.",
                "primary_label" => "See a demo checkout",
                "primary_href" => "https://example.com/demo",
                "secondary_label" => "Talk to commerce",
                "secondary_href" => "contact",
                "specs" => [
                  { "value" => "1.8%", "label" => "card fee, inclusive" },
                  { "value" => "38", "label" => "currencies paid out" },
                  { "value" => "12", "label" => "shopper wallets" },
                  { "value" => "0", "label" => "redirects on card" }
                ],
                "spacing" => "roomy"
              }
            },
            {
              "type" => "feature_tabs",
              "props" => {
                "kicker" => "Grow the shop",
                "heading" => "The parts merchants ask for after the first hundred orders",
                "tabs" => [
                  { "label" => "Online", "title" => "A storefront that still looks like you", "body" => "Sections, a blog, a password page for the drop. Edit copy without calling a developer." },
                  { "label" => "In person", "title" => "A till that knows the website", "body" => "Scan, tap, print a receipt. The same SKU, the same customer, the same return." },
                  { "label" => "Markets", "title" => "Sell next door, then overseas", "body" => "Duties in, language in, a local payment method that does not need a plugin." },
                  { "label" => "B2B", "title" => "Wholesale without a second site", "body" => "Net-30, a catalog per buyer, and an order that still looks like an order." }
                ]
              }
            },
            {
              "type" => "split_checklist",
              "props" => {
                "kicker" => "Operations",
                "heading" => "The unglamorous work, already done",
                "body" => "Tax, shipping, a packing slip that matches the box. You should be packing, not reconciling.",
                "button_label" => "See the admin",
                "button_href" => "https://example.com/demo",
                "items" => [
                  { "title" => "Tax that updates itself", "body" => "Rates for the countries you sell into, including the annoying ones." },
                  { "title" => "Shipping from the shelf", "body" => "Carrier rates, a pickup option, a label from the order screen." },
                  { "title" => "Inventory that does not lie", "body" => "One count for the site, the till and the warehouse." },
                  { "title" => "Payouts you can explain", "body" => "A statement that matches the bank, with fees in plain language." },
                  { "title" => "Staff roles that fit a Saturday", "body" => "A cashier who cannot refund a thousand, a buyer who cannot change the theme." }
                ],
                "surface" => "contrast"
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "kicker" => "The bench",
                "heading" => "Apps for the jobs we will not pretend to own",
                "cells" => [
                  { "span" => "hero", "title" => "Subscriptions that do not fight checkout", "body" => "A second jar every month, paused from the customer account." },
                  { "span" => "unit", "title" => "Reviews", "body" => "Photos from people who already bought." },
                  { "span" => "unit", "title" => "Loyalty", "body" => "A stamp that works online and at the till." },
                  { "span" => "wide", "title" => "Wholesale portals", "body" => "A login per buyer, a catalog per region, net terms that finance already signed off." }
                ],
                "surface" => "muted"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Bring the shop you already have",
                "body" => "We migrate products, customers and the last year of orders. You keep the domain.",
                "button_label" => "Plan a move",
                "button_href" => "contact"
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
          "layout_key" => "harbor_pricing",
          "sections" => [
            {
              "type" => "pricing",
              "props" => {
                "kicker" => "Pricing",
                "heading" => "A plan that fits the shop you have today",
                "subhead" => "Start on Starter. Move when the second staff login appears. Transaction fees fall as you grow.",
                "featured_label" => "Most shops",
                "tiers" => [
                  {
                    "name" => "Starter",
                    "price" => "$29",
                    "cadence" => "per month",
                    "body" => "For the first shop and the first staff member.",
                    "features" => "Online store\nHarbor Checkout\n2 staff accounts\n24/7 chat",
                    "button_label" => "Start a trial",
                    "button_href" => "https://example.com/start",
                    "highlight" => "standard"
                  },
                  {
                    "name" => "Grow",
                    "price" => "$79",
                    "cadence" => "per month",
                    "body" => "For shops with a till, a second location, or a wholesale book.",
                    "features" => "Everything in Starter\nIn-person till\n5 staff accounts\nLower card fees",
                    "button_label" => "Start a trial",
                    "button_href" => "https://example.com/start",
                    "highlight" => "featured"
                  },
                  {
                    "name" => "Plus",
                    "price" => "Custom",
                    "cadence" => "billed annually",
                    "body" => "For brands with more than one market and a finance team.",
                    "features" => "Everything in Grow\nB2B catalogs\nSSO and audit log\nA merchant partner",
                    "button_label" => "Talk to us",
                    "button_href" => "contact",
                    "highlight" => "standard"
                  }
                ],
                "align" => "center"
              }
            },
            {
              "type" => "comparison_table",
              "props" => {
                "kicker" => "Fees and limits",
                "heading" => "What changes when you move up",
                "column_1" => "Starter",
                "column_2" => "Grow",
                "column_3" => "Plus",
                "rows" => [
                  { "title" => "Online store", "value_1" => "✓", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "In-person till", "value_1" => "—", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Staff accounts", "value_1" => "2", "value_2" => "5", "value_3" => "Unlimited" },
                  { "title" => "Card fee", "value_1" => "2.4% + 20¢", "value_2" => "2.1% + 20¢", "value_3" => "Custom" },
                  { "title" => "Markets / languages", "value_1" => "1", "value_2" => "3", "value_3" => "Unlimited" },
                  { "title" => "B2B catalogs", "value_1" => "—", "value_2" => "—", "value_3" => "✓" }
                ],
                "surface" => "muted"
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "The questions every merchant asks",
                "items" => [
                  { "question" => "Is there a trial?", "answer" => "Fourteen days on any plan. We ask for a card only if you keep the shop." },
                  { "question" => "Can I keep my domain?", "answer" => "Yes. Point it when you are ready. We will not put Harbor in the URL unless you want it there." },
                  { "question" => "What if I already have a theme?", "answer" => "Most common themes import. If yours is custom, we will say so before you migrate." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Not sure which plan?",
                "body" => "Tell us last month's orders and whether you have a till. We will point at one.",
                "button_label" => "Ask a merchant partner",
                "button_href" => "contact"
              }
            }
          ]
        },
        {
          "title" => "Stories",
          "slug" => "stories",
          "home" => false,
          "nav_visible" => true,
          "role" => "stories",
          "layout_key" => "harbor_stories",
          "sections" => [
            {
              "type" => "story_index",
              "props" => {
                "kicker" => "Merchant stories",
                "heading" => "How the shop grew",
                "stories" => [
                  { "kicker" => "Kiln Goods", "title" => "From a kiln in the garage to a waitlist in three cities", "body" => "Priya listed one glaze. Harbor handled the rest of the night.", "byline" => "8 min read", "href" => "stories" },
                  { "kicker" => "North Hem", "title" => "A workwear shop that opened a second till without a second system", "byline" => "6 min", "href" => "stories" },
                  { "kicker" => "Salt & Rind", "title" => "Pantry goods, three languages, one checkout", "byline" => "5 min", "href" => "stories" },
                  { "kicker" => "Paper Room", "title" => "A Kyoto stationer who sells out the drop in fourteen minutes", "byline" => "4 min", "href" => "stories" },
                  { "kicker" => "Afterlight", "title" => "Lamps, a showroom, and a wholesale book on the same admin", "byline" => "7 min", "href" => "stories" },
                  { "kicker" => "Field Notes Co.", "title" => "Subscriptions that people actually keep", "byline" => "5 min", "href" => "stories" }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "I did not want a platform. I wanted Friday's orders to be packed by Saturday noon.",
                "attribution" => "Priya Raman",
                "role" => "Kiln Goods",
                "surface" => "muted"
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "heading" => "In their words",
                "items" => [
                  { "quote" => "The first international order was less exciting than I expected. That is a compliment.", "name" => "Ines Costa", "role" => "Salt & Rind" },
                  { "quote" => "We stopped exporting CSVs the month we moved. Finance noticed before marketing did.", "name" => "Tom Alvarez", "role" => "North Hem" },
                  { "quote" => "My photographer edits the theme now. I still do not know what a section group is, and that is fine.", "name" => "Hana Sato", "role" => "Paper Room" }
                ],
                "align" => "center"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Tell us the shop you want to open",
                "body" => "A merchant partner will answer within a day. Bring last year's numbers if you have them.",
                "button_label" => "Write to us",
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
          "layout_key" => "harbor_contact",
          "sections" => [
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Merchant studios",
                "heading" => "Sit with someone who has opened a shop",
                "subhead" => "Bring a product. We will have a test store live before you leave.",
                "places" => [
                  { "name" => "Portland", "address" => "210 NW 10th Avenue\nPortland, OR", "hours" => "Tuesday–Saturday 10:00–18:00", "phone" => "+1 503 555 0190", "button_label" => "Book a desk", "button_href" => "https://example.com/studio" },
                  { "name" => "Montreal", "address" => "88 Rue Saint-Paul Ouest\nMontreal, QC", "hours" => "Wednesday–Sunday 11:00–19:00", "phone" => "+1 514 555 0166", "button_label" => "Book a desk", "button_href" => "https://example.com/studio" },
                  { "name" => "Lisbon", "address" => "4 Rua da Prata\nLisbon", "hours" => "Tuesday–Saturday 10:00–19:00", "phone" => "+351 21 555 0188", "button_label" => "Book a desk", "button_href" => "https://example.com/studio" }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Merchant support",
                "address" => "210 NW 10th Avenue\nPortland, OR",
                "email" => "merchants@example.com",
                "phone" => "+1 503 555 0190",
                "hours" => "Daily, 7:00–22:00 PT"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
