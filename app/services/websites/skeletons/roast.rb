# frozen_string_literal: true

module Websites
  module Skeletons
    # Blue Bottle register: airy and precise — coffees on a shelf, a
    # subscription, cafés with a short menu, and the founding story.
    module Roast
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "roast_home",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Roasted this week",
                "headline" => "Coffee at its peak, at your door",
                "subhead" => "We roast in small batches and ship within 48 hours, so every bag arrives in the days it tastes best.",
                "primary_label" => "Shop coffee",
                "primary_href" => "coffee",
                "secondary_label" => "Find a café",
                "secondary_href" => "cafes"
              }
            },
            {
              "type" => "listing_grid",
              "props" => {
                "kicker" => "This month",
                "heading" => "Coffees we are drinking",
                "aspect" => "square",
                "listings" => [
                  { "title" => "Bright Morning", "meta" => "Blend · citrus, honey, cocoa", "price" => "$22", "badge" => "Staff pick", "href" => "coffee" },
                  { "title" => "Yirgacheffe Konga", "meta" => "Single origin · Ethiopia", "price" => "$26", "href" => "coffee" },
                  { "title" => "Huila La Plata", "meta" => "Single origin · Colombia", "price" => "$24", "href" => "coffee" },
                  { "title" => "Hayes Espresso", "meta" => "Espresso · dark chocolate, cherry", "price" => "$21", "href" => "coffee" }
                ]
              }
            },
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "Never run out",
                "body" => "Choose a coffee and a rhythm — weekly, every two weeks or monthly. Skip, swap or pause from your phone, and every bag ships the day after it is roasted.",
                "image_side" => "left"
              }
            },
            {
              "type" => "steps",
              "props" => {
                "kicker" => "Subscriptions",
                "heading" => "How it works",
                "items" => [
                  { "title" => "Tell us how you brew", "body" => "Pour-over, espresso, French press or a machine at the office." },
                  { "title" => "Pick a rhythm", "body" => "We suggest how much you need; change it whenever you like." },
                  { "title" => "Brew it fresh", "body" => "Bags arrive within four days of roasting, with a recipe card." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Your first bag is on us",
                "body" => "Start a subscription today and we will include a second bag of this month's single origin.",
                "button_label" => "Start a subscription",
                "button_href" => "https://example.com/subscribe"
              }
            }
          ]
        },
        {
          "title" => "Coffee",
          "slug" => "coffee",
          "home" => false,
          "nav_visible" => true,
          "role" => "coffee",
          "layout_key" => "roast_coffee",
          "sections" => [
            {
              "type" => "listing_grid",
              "props" => {
                "kicker" => "Coffee",
                "heading" => "Whole bean and ground",
                "subhead" => "340 g bags. Ground to order for your brew method, or whole bean if you have a grinder.",
                "aspect" => "square",
                "listings" => [
                  { "title" => "Bright Morning", "meta" => "Blend · citrus, honey, cocoa", "price" => "$22", "badge" => "Staff pick", "href" => "https://example.com/coffee/bright-morning" },
                  { "title" => "Yirgacheffe Konga", "meta" => "Ethiopia · jasmine, bergamot", "price" => "$26", "href" => "https://example.com/coffee/konga" },
                  { "title" => "Huila La Plata", "meta" => "Colombia · red apple, caramel", "price" => "$24", "href" => "https://example.com/coffee/la-plata" },
                  { "title" => "Hayes Espresso", "meta" => "Espresso · dark chocolate, cherry", "price" => "$21", "href" => "https://example.com/coffee/hayes" },
                  { "title" => "Night Owl Decaf", "meta" => "Swiss water · toffee, almond", "price" => "$22", "href" => "https://example.com/coffee/decaf" },
                  { "title" => "Brew Kit", "meta" => "Dripper, filters and a scale", "price" => "$68", "badge" => "Gift", "href" => "https://example.com/coffee/brew-kit" }
                ]
              }
            },
            {
              "type" => "faq",
              "props" => {
                "kicker" => "Questions",
                "heading" => "Freshness, explained",
                "items" => [
                  { "question" => "When is my coffee roasted?", "answer" => "The morning before it ships. The roast date is printed on every bag." },
                  { "question" => "How long does it stay fresh?", "answer" => "Coffee tastes best between four and twenty-one days after roasting. Keep it sealed, away from light." },
                  { "question" => "Which grind should I choose?", "answer" => "Pick your brew method at checkout and we will grind to match — or buy whole bean for the best cup." }
                ]
              }
            }
          ]
        },
        {
          "title" => "Cafés",
          "slug" => "cafes",
          "home" => false,
          "nav_visible" => true,
          "role" => "cafes",
          "layout_key" => "roast_cafes",
          "sections" => [
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Cafés",
                "heading" => "Come in for a cup",
                "subhead" => "Every café pours the same coffees we ship, made to order by a barista who has trained for months.",
                "places" => [
                  { "name" => "Hayes Valley", "address" => "315 Linden Street\nSan Francisco, CA", "hours" => "Daily 7:00–17:00", "phone" => "+1 415 555 0161", "button_label" => "Get directions", "button_href" => "https://example.com/cafes/hayes" },
                  { "name" => "Mint Plaza", "address" => "66 Mint Street\nSan Francisco, CA", "hours" => "Daily 7:00–18:00", "phone" => "+1 415 555 0148", "button_label" => "Get directions", "button_href" => "https://example.com/cafes/mint" },
                  { "name" => "Williamsburg", "address" => "160 Berry Street\nBrooklyn, NY", "hours" => "Daily 7:00–19:00", "phone" => "+1 718 555 0119", "button_label" => "Get directions", "button_href" => "https://example.com/cafes/williamsburg" },
                  { "name" => "Arts District", "address" => "582 Mateo Street\nLos Angeles, CA", "hours" => "Daily 7:00–18:00", "phone" => "+1 213 555 0172", "button_label" => "Get directions", "button_href" => "https://example.com/cafes/arts-district" },
                  { "name" => "Aoyama", "address" => "3-13-14 Minami-Aoyama\nTokyo", "hours" => "Daily 8:00–19:00", "phone" => "+81 3 5555 0130", "button_label" => "Get directions", "button_href" => "https://example.com/cafes/aoyama" },
                  { "name" => "Seongsu", "address" => "7 Achasan-ro\nSeoul", "hours" => "Daily 8:00–20:00", "phone" => "+82 2 5555 0150", "button_label" => "Get directions", "button_href" => "https://example.com/cafes/seongsu" }
                ]
              }
            },
            {
              "type" => "price_list",
              "props" => {
                "kicker" => "Menu",
                "heading" => "At the bar",
                "subhead" => "Oat and whole milk at no extra charge.",
                "items" => [
                  { "title" => "Drip", "body" => "Today's single origin, brewed by the cup.", "price" => "$4.50" },
                  { "title" => "Espresso", "body" => "Hayes Espresso, pulled short.", "price" => "$4" },
                  { "title" => "Cortado", "body" => "Equal parts espresso and steamed milk.", "price" => "$5" },
                  { "title" => "New Orleans iced", "body" => "Cold-brewed with chicory, cut with milk and cane sugar.", "price" => "$6" },
                  { "title" => "Liège waffle", "body" => "Pearl sugar, baked to order.", "price" => "$5.50" }
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
          "layout_key" => "roast_story",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "Our story",
                "headline" => "We only sell coffee at its peak of flavour. Everything else follows from that.",
                "body" => "It is why we roast in small batches, why our cafés are small, and why we still weigh every shot."
              }
            },
            {
              "type" => "timeline",
              "props" => {
                "kicker" => "Since 2004",
                "heading" => "From a cart to a roastery",
                "items" => [
                  { "date" => "2004", "title" => "A cart at the farmers market", "body" => "Six pounds of coffee, roasted in a potting shed, sold by the cup." },
                  { "date" => "2008", "title" => "The first café", "body" => "A garage kiosk in an alley, with a line around the block." },
                  { "date" => "2014", "title" => "A roastery of our own", "body" => "Room for two roasters and a tasting lab open to the public." },
                  { "date" => "2019", "title" => "Tokyo and Seoul", "body" => "Our first cafés abroad — built with local architects." },
                  { "date" => "2024", "title" => "Carbon-neutral shipping", "body" => "Every subscription bag now ships in compostable packaging." }
                ]
              }
            },
            {
              "type" => "gallery",
              "props" => {
                "kicker" => "The roastery",
                "heading" => "A morning at the roastery",
                "items" => [
                  { "caption" => "Green coffee, cupped on arrival" },
                  { "caption" => "The 7 am roast" },
                  { "caption" => "Bagged the same afternoon" },
                  { "caption" => "Pour-over training" },
                  { "caption" => "The tasting lab" },
                  { "caption" => "Out for delivery" }
                ]
              }
            }
          ]
        }
      ].freeze
    end
  end
end
