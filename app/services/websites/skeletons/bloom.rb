# frozen_string_literal: true

module Websites
  module Skeletons
    # Glossier register: soft pink, product-first, reviews everywhere — a
    # bestseller shelf, edit tiles, the full shop, the story and stores.
    module Bloom
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "bloom_home",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Skin first. Makeup second.",
                "headline" => "Skincare that looks like skin",
                "subhead" => "Everyday essentials, tested on real people and designed to be worn, not hidden behind.",
                "primary_label" => "Shop bestsellers",
                "primary_href" => "shop",
                "secondary_label" => "Our story",
                "secondary_href" => "story"
              }
            },
            {
              "type" => "listing_grid",
              "props" => {
                "kicker" => "Bestsellers",
                "heading" => "The ones everyone reorders",
                "aspect" => "square",
                "listings" => [
                  { "title" => "Dew Serum", "meta" => "Hydrating serum · 30 ml", "price" => "$32", "rating" => "4.8", "badge" => "Bestseller", "href" => "shop" },
                  { "title" => "Lip Veil", "meta" => "Sheer lipstick · 6 shades", "price" => "$18", "rating" => "4.7", "href" => "shop" },
                  { "title" => "Whip Cream", "meta" => "Moisturiser · 50 ml", "price" => "$26", "rating" => "4.9", "href" => "shop" },
                  { "title" => "Soft Screen SPF 40", "meta" => "Daily sunscreen · 50 ml", "price" => "$28", "rating" => "4.6", "badge" => "New", "href" => "shop" }
                ]
              }
            },
            {
              "type" => "showcase_tiles",
              "props" => {
                "tiles" => [
                  {
                    "kicker" => "The skincare edit",
                    "title" => "Morning, sorted",
                    "body" => "Cleanse, serum, screen. Three steps, four minutes.",
                    "primary_label" => "Shop skincare",
                    "primary_href" => "shop",
                    "tone" => "light",
                    "size" => "half"
                  },
                  {
                    "kicker" => "The makeup edit",
                    "title" => "Barely there",
                    "body" => "Sheer tints and balms you can put on without a mirror.",
                    "primary_label" => "Shop makeup",
                    "primary_href" => "shop",
                    "tone" => "light",
                    "size" => "half"
                  }
                ]
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "kicker" => "Reviews",
                "heading" => "40,000 five-star reviews and counting",
                "items" => [
                  { "quote" => "The only lip colour that survives my morning coffee. I own it in every shade.", "name" => "Jess M.", "role" => "Verified buyer · Lip Veil" },
                  { "quote" => "My skin looks like skin, just on a good day. I have stopped wearing foundation.", "name" => "Priya K.", "role" => "Verified buyer · Dew Serum" },
                  { "quote" => "Finally a sunscreen that does not leave a white cast or pill under makeup.", "name" => "Ana R.", "role" => "Verified buyer · Soft Screen" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Get first access to new launches",
                "body" => "Join the list for early drops, shade previews and 10% off your first order.",
                "button_label" => "Join the list",
                "button_href" => "https://example.com/join"
              }
            }
          ]
        },
        {
          "title" => "Shop",
          "slug" => "shop",
          "home" => false,
          "nav_visible" => true,
          "role" => "shop",
          "layout_key" => "bloom_shop",
          "sections" => [
            {
              "type" => "listing_grid",
              "props" => {
                "kicker" => "Shop all",
                "heading" => "Everything we make",
                "subhead" => "Free shipping over $30 and free returns — even if you have opened it.",
                "aspect" => "portrait",
                "listings" => [
                  { "title" => "Dew Serum", "meta" => "Hydrating serum", "price" => "$32", "rating" => "4.8", "badge" => "Bestseller", "href" => "https://example.com/shop/dew-serum" },
                  { "title" => "Lip Veil", "meta" => "Sheer lipstick", "price" => "$18", "rating" => "4.7", "href" => "https://example.com/shop/lip-veil" },
                  { "title" => "Whip Cream", "meta" => "Moisturiser", "price" => "$26", "rating" => "4.9", "href" => "https://example.com/shop/whip-cream" },
                  { "title" => "Soft Screen SPF 40", "meta" => "Daily sunscreen", "price" => "$28", "rating" => "4.6", "badge" => "New", "href" => "https://example.com/shop/soft-screen" },
                  { "title" => "Botanical Oil", "meta" => "Face oil", "price" => "$30", "rating" => "4.7", "href" => "https://example.com/shop/botanical-oil" },
                  { "title" => "Pop Lip", "meta" => "Bold lipstick · 5 shades", "price" => "$20", "rating" => "4.8", "href" => "https://example.com/shop/pop-lip" },
                  { "title" => "Night Drops", "meta" => "Overnight serum", "price" => "$34", "rating" => "4.5", "href" => "https://example.com/shop/night-drops" },
                  { "title" => "The Starter Set", "meta" => "Four minis", "price" => "$40", "badge" => "Gift", "href" => "https://example.com/shop/starter-set" }
                ]
              }
            },
            {
              "type" => "faq",
              "props" => {
                "kicker" => "Help",
                "heading" => "Shipping and returns",
                "items" => [
                  { "question" => "How fast is shipping?", "answer" => "Orders ship within one business day and arrive in two to five." },
                  { "question" => "Can I return something I have opened?", "answer" => "Yes. If it is not right for you, return it within 30 days for a full refund." },
                  { "question" => "Are your products cruelty-free?", "answer" => "Always. We never test on animals and neither do our suppliers." }
                ]
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
          "layout_key" => "bloom_story",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "Our story",
                "headline" => "We started as a blog asking one question: what is actually in your bathroom cabinet?",
                "body" => "Ten thousand answers later, we made the products readers kept asking for — and we still ask before we launch anything."
              }
            },
            {
              "type" => "alternating_features",
              "props" => {
                "kicker" => "What we believe",
                "heading" => "Made with the people who wear it",
                "items" => [
                  { "title" => "Tested on real skin", "body" => "Every formula goes to a community panel of five hundred people before it goes to a shelf." },
                  { "title" => "Fewer, better steps", "body" => "No twelve-step routines. Each product does one thing beautifully." },
                  { "title" => "Kind by default", "body" => "Cruelty-free, fragrance-optional and packaged in recycled materials." }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "Beauty should feel like a conversation with a friend, not a lecture from a counter.",
                "attribution" => "Mia Laurent",
                "role" => "Founder"
              }
            }
          ]
        },
        {
          "title" => "Stores",
          "slug" => "stores",
          "home" => false,
          "nav_visible" => true,
          "role" => "stores",
          "layout_key" => "bloom_stores",
          "sections" => [
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Stores",
                "heading" => "Come and try everything",
                "subhead" => "Every store has testers for every shade, and nobody will follow you around.",
                "places" => [
                  { "name" => "SoHo", "address" => "123 Lafayette Street\nNew York, NY", "hours" => "Daily 10:00–20:00", "phone" => "+1 212 555 0133", "button_label" => "Get directions", "button_href" => "https://example.com/stores/soho" },
                  { "name" => "Silver Lake", "address" => "3800 Sunset Boulevard\nLos Angeles, CA", "hours" => "Daily 11:00–19:00", "phone" => "+1 323 555 0171", "button_label" => "Get directions", "button_href" => "https://example.com/stores/silver-lake" },
                  { "name" => "Covent Garden", "address" => "18 Neal Street\nLondon WC2H", "hours" => "Monday–Saturday 10:00–20:00", "phone" => "+44 20 5555 0122", "button_label" => "Get directions", "button_href" => "https://example.com/stores/covent-garden" }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Talk to us",
                "address" => "123 Lafayette Street\nNew York, NY",
                "email" => "hello@example.com",
                "phone" => "+1 212 555 0100",
                "hours" => "Monday–Friday, 9:00–18:00 ET"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
