# frozen_string_literal: true

module Websites
  # Seeds platform WebsiteLayout / WebsiteSkeleton rows from Ruby catalogs.
  # New keys are inserted; existing rows keep owner copy and only receive
  # blank media fills from Websites::Media.
  module Catalog
    EXTRA_LAYOUTS = [
      {
        "key" => "article",
        "sections" => [
          {
            "type" => "rich_text",
            "props" => {
              "heading" => "A page of its own",
              "body" => "Use this layout for a long read: one heading, a body that can breathe, nothing else competing for attention."
            }
          }
        ]
      },
      {
        "key" => "manifesto",
        "sections" => [
          {
            "type" => "hero_cinematic",
            "props" => {
              "kicker" => "Belief",
              "headline" => "We make the quiet work visible",
              "subhead" => "A single claim, then the proof. No clutter, no competing hero.",
              "primary_label" => "Read the story",
              "primary_href" => "about",
              "tone" => "dark"
            }
          },
          {
            "type" => "quote",
            "props" => {
              "quote" => "If it needs a caption to be understood, it is not finished.",
              "attribution" => "Studio note",
              "role" => "Wall text"
            }
          },
          {
            "type" => "rich_text",
            "props" => {
              "heading" => "What we will not do",
              "body" => "We will not ship a page that apologizes for itself. The type is large because the sentence earned it. The space around it is the point."
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Start here",
              "body" => "One next step. Not a menu of maybes.",
              "button_label" => "Contact",
              "button_href" => "contact"
            }
          }
        ]
      },
      {
        "key" => "gallery",
        "sections" => [
          {
            "type" => "hero_cinematic",
            "props" => {
              "kicker" => "Selected work",
              "headline" => "Pictures first, then the names",
              "subhead" => "A catalog page in the museum register — large frames, short labels.",
              "primary_label" => "See the work",
              "primary_href" => "about",
              "tone" => "light"
            }
          },
          {
            "type" => "card_grid",
            "props" => {
              "heading" => "On view",
              "subhead" => "Three rooms. Walk them in order, or not.",
              "cards" => [
                { "title" => "North gallery", "body" => "Daylight, timber, and the long wall.", "href" => "about" },
                { "title" => "Court", "body" => "Open to the weather on purpose.", "href" => "about" },
                { "title" => "Study", "body" => "Smaller work. Sit if you like.", "href" => "about" }
              ]
            }
          },
          {
            "type" => "quote",
            "props" => {
              "quote" => "Hang it lower. People look with their feet as much as their eyes.",
              "attribution" => "Hanging crew"
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Visit the rooms",
              "body" => "The site is a map. The work is on the walls.",
              "button_label" => "Plan a visit",
              "button_href" => "contact"
            }
          }
        ]
      },
      {
        "key" => "longform",
        "sections" => [
          {
            "type" => "rich_text",
            "props" => {
              "heading" => "Read this slowly",
              "body" => "A long page for a long argument. Alternate image and text so the eye can rest, then continue."
            }
          },
          {
            "type" => "split_image_text",
            "props" => {
              "heading" => "The first turn",
              "body" => "Place a still here. The caption belongs in the heading, not under the picture.",
              "image_side" => "left"
            }
          },
          {
            "type" => "quote",
            "props" => {
              "quote" => "Most pages try to say everything. This one says one thing until it is true."
            }
          },
          {
            "type" => "split_image_text",
            "props" => {
              "heading" => "The second turn",
              "body" => "Swap the image to the other side. The reader should feel the page breathe.",
              "image_side" => "right"
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Keep going",
              "body" => "When the essay ends, give them somewhere kind to land.",
              "button_label" => "Continue",
              "button_href" => "about"
            }
          }
        ]
      },
      {
        "key" => "launch",
        "sections" => [
          {
            "type" => "hero_centered",
            "props" => {
              "eyebrow" => "New",
              "headline" => "Launch something people talk about",
              "subhead" => "A centered headline, a clear next step and the product itself — nothing competing for attention.",
              "primary_label" => "Get started",
              "primary_href" => "contact",
              "secondary_label" => "Learn more",
              "secondary_href" => "about"
            }
          },
          {
            "type" => "logo_cloud",
            "props" => {
              "heading" => "Used by teams at",
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
            "type" => "feature_grid",
            "props" => {
              "kicker" => "Why us",
              "heading" => "Three reasons to switch",
              "items" => [
                { "title" => "Faster", "body" => "Say what it does in one line, then prove it in the next." },
                { "title" => "Simpler", "body" => "Fewer settings, better defaults, nothing to maintain." },
                { "title" => "Safer", "body" => "Security and privacy handled before you ask." }
              ]
            }
          },
          {
            "type" => "testimonials",
            "props" => {
              "heading" => "What early customers say",
              "items" => [
                { "quote" => "It replaced three tools in our first week.", "name" => "Maya Chen", "role" => "Operations lead" },
                { "quote" => "The fastest onboarding we have ever done.", "name" => "Daniel Osei", "role" => "Founder" },
                { "quote" => "Our team actually enjoys using it.", "name" => "Sara Lindqvist", "role" => "Head of Product" }
              ]
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Ready when you are",
              "body" => "Start free and invite your team when it clicks.",
              "button_label" => "Start now",
              "button_href" => "contact"
            }
          }
        ]
      },
      {
        "key" => "pricing",
        "sections" => [
          {
            "type" => "pricing",
            "props" => {
              "kicker" => "Pricing",
              "heading" => "Simple plans, no surprises",
              "subhead" => "Pick a plan now and change it whenever you like.",
              "tiers" => [
                {
                  "name" => "Starter",
                  "price" => "$0",
                  "cadence" => "per month",
                  "body" => "For individuals trying things out.",
                  "features" => "Core features\nCommunity support",
                  "button_label" => "Start free",
                  "button_href" => "contact",
                  "highlight" => "standard"
                },
                {
                  "name" => "Team",
                  "price" => "$24",
                  "cadence" => "per seat / month",
                  "body" => "For growing teams.",
                  "features" => "Everything in Starter\nCollaboration\nPriority support",
                  "button_label" => "Start a trial",
                  "button_href" => "contact",
                  "highlight" => "featured"
                },
                {
                  "name" => "Business",
                  "price" => "Custom",
                  "cadence" => "billed annually",
                  "body" => "For organisations at scale.",
                  "features" => "Everything in Team\nSSO and audit log\nDedicated manager",
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
              "heading" => "Common questions",
              "items" => [
                { "question" => "Is there a free trial?", "answer" => "Yes — fourteen days on any paid plan, no card required." },
                { "question" => "Can I cancel anytime?", "answer" => "Yes. You keep access until the end of your billing period." }
              ]
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Still deciding?",
              "body" => "Talk to a person and get a straight answer.",
              "button_label" => "Contact us",
              "button_href" => "contact"
            }
          }
        ]
      },
      {
        "key" => "portfolio",
        "sections" => [
          {
            "type" => "statement",
            "props" => { "kicker" => "Studio", "headline" => "We design things that are meant to be kept.", "body" => "An independent practice working across identity, print and space." }
          },
          {
            "type" => "gallery",
            "props" => {
              "heading" => "Selected work",
              "items" => [
                { "caption" => "Identity" },
                { "caption" => "Editorial" },
                { "caption" => "Signage" },
                { "caption" => "Packaging" },
                { "caption" => "Exhibition" }
              ]
            }
          },
          {
            "type" => "logo_cloud",
            "props" => {
              "heading" => "Clients",
              "items" => [
                { "name" => "City Museum" },
                { "name" => "Northwind" },
                { "name" => "Atlas" },
                { "name" => "Kiln" }
              ]
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Let's make something",
              "body" => "Tell us about the project and the timeline.",
              "button_label" => "Get in touch",
              "button_href" => "contact"
            }
          }
        ]
      },
      {
        "key" => "menu",
        "sections" => [
          {
            "type" => "hero_cinematic",
            "props" => {
              "kicker" => "Tonight",
              "headline" => "The seasonal menu",
              "subhead" => "What the growers brought us this week, cooked simply.",
              "tone" => "light"
            }
          },
          {
            "type" => "price_list",
            "props" => {
              "heading" => "Menu",
              "items" => [
                { "title" => "Bread and cultured butter", "body" => "Sourdough from the morning bake.", "price" => "8" },
                { "title" => "Beetroot and smoked cream", "body" => "Roasted in embers, dressed with rose.", "price" => "16" },
                { "title" => "Hake, mussels and dill", "body" => "From the harbour this morning.", "price" => "32" },
                { "title" => "Pine and honey", "body" => "Frozen, burnt and whipped.", "price" => "12" }
              ]
            }
          },
          {
            "type" => "contact_info",
            "props" => {
              "heading" => "Book a table",
              "address" => "12 Harbour Street",
              "email" => "table@example.com",
              "phone" => "+1 555 012 3000",
              "hours" => "Wednesday–Sunday from 17:00"
            }
          }
        ]
      },
      {
        "key" => "journal",
        "sections" => [
          {
            "type" => "statement",
            "props" => { "kicker" => "Journal", "headline" => "Notes from the studio, published when there is something to say." }
          },
          {
            "type" => "gallery",
            "props" => {
              "items" => [
                { "caption" => "Morning light" },
                { "caption" => "Work in progress" },
                { "caption" => "The long table" }
              ]
            }
          },
          {
            "type" => "rich_text",
            "props" => {
              "heading" => "An essay, not an update",
              "body" => "Use this page for writing that deserves room: a single argument, told at the pace it needs.\n\nPair the words with a few photographs and let the page breathe."
            }
          }
        ]
      },
      {
        "key" => "process",
        "sections" => [
          {
            "type" => "hero_split",
            "props" => {
              "eyebrow" => "How it works",
              "headline" => "A clear path from first call to finished work",
              "subhead" => "Show customers exactly what happens next — and how long it takes.",
              "primary_label" => "Book a call",
              "primary_href" => "contact"
            }
          },
          {
            "type" => "steps",
            "props" => {
              "heading" => "Our process",
              "items" => [
                { "title" => "Discover", "body" => "We listen, ask questions and agree on what success looks like." },
                { "title" => "Design", "body" => "We share early work often, while it is still easy to change." },
                { "title" => "Deliver", "body" => "We launch, measure and stay close while it settles in." }
              ]
            }
          },
          {
            "type" => "feature_grid",
            "props" => {
              "heading" => "What you can expect",
              "items" => [
                { "title" => "One point of contact", "body" => "A lead who knows your project end to end." },
                { "title" => "Fixed timelines", "body" => "Dates agreed up front and kept." },
                { "title" => "Clear pricing", "body" => "No surprise invoices." }
              ]
            }
          },
          {
            "type" => "faq",
            "props" => {
              "heading" => "Questions",
              "items" => [
                { "question" => "How long does a typical project take?", "answer" => "Most projects take six to ten weeks from kickoff to launch." }
              ]
            }
          }
        ]
      },
      {
        "key" => "showcase",
        "sections" => [
          {
            "type" => "showcase_tiles",
            "props" => {
              "tiles" => [
                { "kicker" => "New", "title" => "The flagship", "body" => "Everything we know, in one product.", "primary_label" => "Learn more", "primary_href" => "about", "secondary_label" => "Buy", "secondary_href" => "contact", "tone" => "dark", "size" => "full" },
                { "title" => "The compact one", "body" => "All the essentials, half the size.", "primary_label" => "Learn more", "primary_href" => "about", "tone" => "light", "size" => "half" },
                { "title" => "The pro edition", "body" => "For people who push it every day.", "primary_label" => "Learn more", "primary_href" => "about", "tone" => "dark", "size" => "half" }
              ]
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "See them side by side",
              "body" => "Visit us to try every model before you choose.",
              "button_label" => "Find us",
              "button_href" => "contact"
            }
          }
        ]
      },
      {
        "key" => "compare",
        "sections" => [
          {
            "type" => "comparison_table",
            "props" => {
              "kicker" => "Compare",
              "heading" => "Find the right plan",
              "subhead" => "Every plan includes support and free updates.",
              "column_1" => "Starter",
              "column_2" => "Team",
              "column_3" => "Business",
              "rows" => [
                { "title" => "Users", "value_1" => "1", "value_2" => "Up to 20", "value_3" => "Unlimited" },
                { "title" => "Storage", "value_1" => "10 GB", "value_2" => "1 TB", "value_3" => "Unlimited" },
                { "title" => "Shared workspaces", "value_1" => "—", "value_2" => "✓", "value_3" => "✓" },
                { "title" => "Single sign-on", "value_1" => "—", "value_2" => "—", "value_3" => "✓" },
                { "title" => "Priority support", "value_1" => "—", "value_2" => "✓", "value_3" => "✓" }
              ]
            }
          },
          {
            "type" => "faq",
            "props" => {
              "heading" => "Questions",
              "items" => [
                { "question" => "Can I change plans later?", "answer" => "Yes. Upgrade or downgrade at any time; we prorate the difference." }
              ]
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Still deciding?",
              "body" => "Talk to us and we will recommend the plan that fits.",
              "button_label" => "Contact sales",
              "button_href" => "contact"
            }
          }
        ]
      },
      {
        "key" => "newsroom",
        "sections" => [
          {
            "type" => "story_index",
            "props" => {
              "kicker" => "Latest",
              "heading" => "News",
              "stories" => [
                { "kicker" => "Announcement", "title" => "The biggest change we have made in ten years", "body" => "What is new, why we did it and what it means for you.", "byline" => "6 min read" },
                { "kicker" => "Company", "title" => "Opening our second studio", "byline" => "3 min read" },
                { "kicker" => "Product", "title" => "Five features you asked for", "byline" => "4 min read" },
                { "kicker" => "People", "title" => "Meet the new team", "byline" => "Profile" },
                { "kicker" => "Report", "title" => "Our year in numbers", "byline" => "Annual review" },
                { "kicker" => "Events", "title" => "See us on tour", "byline" => "Dates" },
                { "kicker" => "Press", "title" => "In the news", "byline" => "Coverage" }
              ]
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Get the news first",
              "body" => "One email a month. No noise.",
              "button_label" => "Subscribe",
              "button_href" => "contact"
            }
          }
        ]
      },
      {
        "key" => "listings",
        "sections" => [
          {
            "type" => "listing_grid",
            "props" => {
              "kicker" => "Available now",
              "heading" => "Browse the collection",
              "subhead" => "Updated every week. Ask us about anything you do not see.",
              "aspect" => "landscape",
              "listings" => [
                { "title" => "The Garden House", "meta" => "4 rooms · private garden", "price" => "From $420", "rating" => "4.9", "badge" => "New" },
                { "title" => "The Loft", "meta" => "2 rooms · city views", "price" => "From $260", "rating" => "4.8" },
                { "title" => "The Cabin", "meta" => "3 rooms · by the lake", "price" => "From $310", "rating" => "4.9" },
                { "title" => "The Studio", "meta" => "1 room · walk to everything", "price" => "From $180", "rating" => "4.7" },
                { "title" => "The Farmhouse", "meta" => "6 rooms · 20 acres", "price" => "From $560", "rating" => "5.0", "badge" => "Popular" },
                { "title" => "The Beach Hut", "meta" => "2 rooms · steps to the sand", "price" => "From $290", "rating" => "4.8" }
              ]
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Looking for something specific?",
              "body" => "Tell us what you need and we will send a shortlist within a day.",
              "button_label" => "Ask us",
              "button_href" => "contact"
            }
          }
        ]
      },
      {
        "key" => "stores",
        "sections" => [
          {
            "type" => "locations",
            "props" => {
              "kicker" => "Visit",
              "heading" => "Find us",
              "subhead" => "Walk in any time, or book ahead for a one-to-one appointment.",
              "places" => [
                { "name" => "Downtown", "address" => "120 Main Street\nYour City", "hours" => "Daily 10:00–19:00", "phone" => "+1 555 0100", "button_label" => "Get directions", "button_href" => "https://example.com/map" },
                { "name" => "Riverside", "address" => "8 Water Lane\nYour City", "hours" => "Tuesday–Sunday 11:00–18:00", "phone" => "+1 555 0101", "button_label" => "Get directions", "button_href" => "https://example.com/map" },
                { "name" => "Old Town", "address" => "45 Market Square\nYour City", "hours" => "Monday–Saturday 9:00–17:00", "phone" => "+1 555 0102", "button_label" => "Get directions", "button_href" => "https://example.com/map" }
              ]
            }
          },
          {
            "type" => "contact_info",
            "props" => {
              "heading" => "Questions before you visit?",
              "email" => "hello@example.com",
              "phone" => "+1 555 0100",
              "hours" => "Monday–Friday, 9:00–17:00"
            }
          }
        ]
      },
      {
        "key" => "heritage",
        "sections" => [
          {
            "type" => "statement",
            "props" => {
              "kicker" => "Our history",
              "headline" => "We have been doing one thing well for a long time.",
              "body" => "The people have changed. The standard has not."
            }
          },
          {
            "type" => "timeline",
            "props" => {
              "kicker" => "Milestones",
              "heading" => "How we got here",
              "items" => [
                { "date" => "1998", "title" => "The first workshop", "body" => "Two people, one room and a waiting list." },
                { "date" => "2006", "title" => "A place of our own", "body" => "We bought the building we still work from." },
                { "date" => "2015", "title" => "The next generation", "body" => "Our first apprentices became partners." },
                { "date" => "2024", "title" => "Still independent", "body" => "No investors, no shortcuts, no plans to change that." }
              ]
            }
          },
          {
            "type" => "quote",
            "props" => {
              "quote" => "Make it well, make it last, and stand behind it.",
              "attribution" => "Founder",
              "role" => "Written on the workshop wall"
            }
          }
        ]
      },
      {
        "key" => "conference",
        "sections" => [
          {
            "type" => "hero_cinematic",
            "props" => {
              "kicker" => "One day · One city",
              "headline" => "The conference for people who build",
              "subhead" => "Talks, workshops and the hallway conversations that make the trip worth it.",
              "primary_label" => "Get tickets",
              "primary_href" => "contact",
              "secondary_label" => "See the schedule",
              "secondary_href" => "about",
              "tone" => "dark"
            }
          },
          {
            "type" => "agenda",
            "props" => {
              "kicker" => "Schedule",
              "heading" => "The day at a glance",
              "sessions" => [
                { "time" => "09:00", "title" => "Opening keynote", "speaker" => "Our founder", "track" => "Main stage" },
                { "time" => "10:30", "title" => "What we learned shipping every week", "speaker" => "Guest speaker", "track" => "Main stage" },
                { "time" => "13:00", "title" => "Hands-on workshops", "body" => "Pick one of four rooms. Laptops recommended.", "track" => "Workshops" },
                { "time" => "17:00", "title" => "Closing panel and drinks", "track" => "Terrace" }
              ]
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Save your seat",
              "body" => "Early tickets are limited and sell out every year.",
              "button_label" => "Get tickets",
              "button_href" => "contact"
            }
          }
        ]
      },
      {
        "key" => "spotlight",
        "sections" => [
          {
            "type" => "announcement",
            "props" => {
              "badge" => "New",
              "body" => "Air 3 — thinner, quieter, all-day battery. Available Friday.",
              "link_label" => "Pre-order",
              "href" => "https://example.com/order",
              "surface" => "accent"
            }
          },
          {
            "type" => "product_spotlight",
            "props" => {
              "kicker" => "Air 3",
              "headline" => "The most personal computer we have ever made",
              "subhead" => "A 14-inch panel that disappears into the desk. A keyboard that barely clicks. Fourteen hours, measured the way you actually work.",
              "primary_label" => "Pre-order",
              "primary_href" => "https://example.com/order",
              "secondary_label" => "Watch the film",
              "secondary_href" => "https://example.com/film",
              "specs" => [
                { "value" => "1.09 kg", "label" => "the whole machine" },
                { "value" => "14 hr", "label" => "mixed use, our test" },
                { "value" => "12 mp", "label" => "center-stage camera" },
                { "value" => "3", "label" => "finishes, all aluminium" }
              ],
              "spacing" => "roomy"
            }
          },
          {
            "type" => "metrics",
            "props" => {
              "kicker" => "Inside",
              "heading" => "Faster where it matters",
              "items" => [
                { "value" => "2×", "label" => "graphics", "body" => "Against Air 2, on the same 4K timeline." },
                { "value" => "18%", "label" => "thinner at the hinge", "body" => "The reason it sits flat on a wooden desk." },
                { "value" => "0 fans", "label" => "you can hear", "body" => "A vapour chamber, not a compromise." },
                { "value" => "1 night", "label" => "to 80%", "body" => "On the 35 W brick in the box." }
              ],
              "align" => "center",
              "surface" => "muted"
            }
          },
          {
            "type" => "feature_tabs",
            "props" => {
              "kicker" => "Look closer",
              "heading" => "The decisions you will live with",
              "tabs" => [
                { "label" => "Display", "title" => "A panel that gets out of the way", "body" => "500 nits, a 120 Hz refresh when the work needs it, and a coating that does not pick up the room." },
                { "label" => "Keyboard", "title" => "1 mm of travel, and a hush", "body" => "We rebuilt the scissor. You will hear the room, not the keys." },
                { "label" => "Camera", "title" => "You stay in the frame", "body" => "Center stage, a desk-height lens, and a cutout that does not steal the menu bar." },
                { "label" => "Ports", "title" => "Two, on purpose", "body" => "Power and a display on one. A second for the rest of the day." }
              ],
              "align" => "start"
            }
          },
          {
            "type" => "image_banner",
            "props" => {
              "kicker" => "Finishes",
              "headline" => "Mist, Ink, and a copper we almost did not ship",
              "body" => "Anodised through, not painted. The copper is the one on the table in the film.",
              "button_label" => "See them in a studio",
              "button_href" => "contact",
              "height" => "medium",
              "placement" => "center"
            }
          },
          {
            "type" => "cta_split",
            "props" => {
              "kicker" => "Friday",
              "headline" => "Pre-order tonight. We will have it on the desk by the 18th.",
              "body" => "Configure a finish, a memory size, an engraving. Change your mind until it ships.",
              "primary_label" => "Pre-order Air 3",
              "primary_href" => "https://example.com/order",
              "secondary_label" => "Find a studio",
              "secondary_href" => "contact",
              "image_side" => "right"
            }
          }
        ]
      },
      {
        "key" => "campaign",
        "sections" => [
          {
            "type" => "image_banner",
            "props" => {
              "kicker" => "Fall / Winter",
              "headline" => "Run the city like it is yours",
              "body" => "The Apex pack — a jacket that packs into itself, a shoe that holds a wet road, a watch that just counts.",
              "button_label" => "Shop the pack",
              "button_href" => "https://example.com/shop",
              "height" => "tall",
              "placement" => "bottom"
            }
          },
          {
            "type" => "collection_rail",
            "props" => {
              "kicker" => "The pack",
              "heading" => "Four pieces. Wear them in any order.",
              "aspect" => "portrait",
              "items" => [
                { "title" => "Apex jacket", "meta" => "Packs to a fist", "href" => "https://example.com/shop" },
                { "title" => "Apex shoe", "meta" => "Wet-road rubber", "href" => "https://example.com/shop" },
                { "title" => "Stride tight", "meta" => "Half-zip, reflective", "href" => "https://example.com/shop" },
                { "title" => "Lap watch", "meta" => "A number. No feed.", "href" => "https://example.com/shop" },
                { "title" => "Carry vest", "meta" => "Bottle, keys, a layer", "href" => "https://example.com/shop" },
                { "title" => "Dawn cap", "meta" => "Unstructured", "href" => "https://example.com/shop" }
              ],
              "align" => "start"
            }
          },
          {
            "type" => "image_banner",
            "props" => {
              "kicker" => "Members",
              "headline" => "A Saturday group run. No pace police.",
              "body" => "Fourteen cities, dawn. Show up. We will have water and a way home.",
              "button_label" => "Find a run",
              "button_href" => "contact",
              "height" => "medium",
              "placement" => "center"
            }
          },
          {
            "type" => "metrics",
            "props" => {
              "heading" => "Last season",
              "items" => [
                { "value" => "212", "label" => "group runs", "body" => "Every one of them free, and none of them a product launch." },
                { "value" => "38k", "label" => "pairs returned to the track", "body" => "Worn shoes, ground into a new outsole." },
                { "value" => "14", "label" => "cities at dawn", "body" => "From Lisbon to Seoul, same hour, different light." },
                { "value" => "0", "label" => "finish-line banners", "body" => "You came to run. We will not make you pose." }
              ],
              "align" => "center",
              "surface" => "contrast"
            }
          },
          {
            "type" => "cta_split",
            "props" => {
              "kicker" => "Apex",
              "headline" => "The pack is in the shop. The run is on Saturday.",
              "body" => "Buy one piece or all four. The group run does not require a receipt.",
              "primary_label" => "Shop Apex",
              "primary_href" => "https://example.com/shop",
              "secondary_label" => "Find Saturday",
              "secondary_href" => "contact",
              "image_side" => "left"
            }
          }
        ]
      },
      {
        "key" => "tour",
        "sections" => [
          {
            "type" => "announcement",
            "props" => {
              "badge" => "2.4",
              "body" => "Cycles can now start from a document. The board updates itself.",
              "link_label" => "Read the log",
              "href" => "https://example.com/changelog",
              "surface" => "accent"
            }
          },
          {
            "type" => "hero_centered",
            "props" => {
              "eyebrow" => "A product tour",
              "headline" => "Issue tracking that stays out of the way",
              "subhead" => "Keyboard first, cycles that tell the truth, and a board you will actually open on a Monday.",
              "primary_label" => "Start free",
              "primary_href" => "https://example.com/start",
              "secondary_label" => "See a workspace",
              "secondary_href" => "https://example.com/demo",
              "media_mode" => "none"
            }
          },
          {
            "type" => "feature_tabs",
            "props" => {
              "kicker" => "The tour",
              "heading" => "Four things, then you can decide",
              "subhead" => "Click a tab. Each one is a real screen, not a metaphor.",
              "tabs" => [
                { "label" => "Issues", "title" => "A sentence is enough to start", "body" => "Title, then the fields that matter. Everything else waits. Command-K from anywhere." },
                { "label" => "Cycles", "title" => "Two weeks, a burn that does not lie", "body" => "What you planned, what moved, what you slipped on purpose. No theatre." },
                { "label" => "Projects", "title" => "A home for the bet", "body" => "A brief, a date, the issues that belong. Not a folder of tickets." },
                { "label" => "Insights", "title" => "The one chart your lead already asks for", "body" => "Cycle time, sneak-ins, the work that aged. Export if finance wants a slide." }
              ],
              "align" => "start",
              "spacing" => "roomy"
            }
          },
          {
            "type" => "split_checklist",
            "props" => {
              "kicker" => "Why teams switch",
              "heading" => "The last tool was not slow. It was noisy.",
              "body" => "We kept the parts that help a team finish, and deleted the parts that create a status meeting.",
              "button_label" => "Start a workspace",
              "button_href" => "https://example.com/start",
              "items" => [
                { "title" => "Keyboard first, always", "body" => "Create, assign, close, jump. The mouse is optional." },
                { "title" => "Notifications you can trust", "body" => "Only when something needs you. Slack if you want it; never both." },
                { "title" => "A graph that stays fast", "body" => "A hundred thousand issues. The board still opens in a breath." },
                { "title" => "Permissions that match the org chart", "body" => "Guests see a project. They do not see last quarter." }
              ],
              "surface" => "contrast"
            }
          },
          {
            "type" => "metrics",
            "props" => {
              "heading" => "After the first cycle",
              "items" => [
                { "value" => "11 min", "label" => "median time to first issue", "body" => "From invite accepted to something on the board." },
                { "value" => "40%", "label" => "fewer status meetings", "body" => "Self-reported, thirty days in. The board became the meeting." },
                { "value" => "2.1s", "label" => "p95 to open the app", "body" => "Measured on a four-year-old laptop. We keep the receipt." },
                { "value" => "0", "label" => "plugins required", "body" => "Git, Slack, the calendar. The rest is a conversation." }
              ],
              "align" => "center",
              "surface" => "muted"
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Bring last week's board with you",
              "body" => "Importers for the usual suspects. We will not make you retype the work.",
              "button_label" => "Start free",
              "button_href" => "https://example.com/start"
            }
          }
        ]
      },
      {
        "key" => "impact",
        "sections" => [
          {
            "type" => "statement",
            "props" => {
              "kicker" => "Annual report",
              "headline" => "The year in the numbers we will stand behind.",
              "body" => "Volume, reliability, and the money that moved. No vanity metrics. If a figure is here, finance signed it."
            }
          },
          {
            "type" => "metrics",
            "props" => {
              "kicker" => "Volume",
              "heading" => "What moved",
              "subhead" => "Twelve months, every region we operate in.",
              "items" => [
                { "value" => "$184B", "label" => "payment volume", "body" => "Card, wallet, bank, and the local methods that still matter." },
                { "value" => "99.999%", "label" => "authorisation uptime", "body" => "Five minutes of incident time, published, with the post-mortem." },
                { "value" => "46", "label" => "countries live", "body" => "A local entity, a local payout, a local support hour." },
                { "value" => "12 ms", "label" => "p50 to authorise", "body" => "Same region as the merchant. We do not route for fun." }
              ],
              "align" => "center",
              "surface" => "muted"
            }
          },
          {
            "type" => "split_checklist",
            "props" => {
              "kicker" => "How we report",
              "heading" => "The rules we will not break for a slide",
              "body" => "If we cannot explain a number in a sentence, it does not go on this page.",
              "button_label" => "Read the full report",
              "button_href" => "https://example.com/report",
              "items" => [
                { "title" => "Uptime is incident time, not a ping", "body" => "If a merchant could not charge, it counts. Marketing pings do not." },
                { "title" => "Volume is settled, not authorised", "body" => "Authorised-and-voided is not a brag." },
                { "title" => "Every region has a name", "body" => "No 'rest of world' bucket hiding a problem." },
                { "title" => "Fees are published in the same units", "body" => "A basis point is a basis point. We will not mix in FX to look cheaper." }
              ]
            }
          },
          {
            "type" => "feature_grid",
            "props" => {
              "kicker" => "Where it went",
              "heading" => "The work behind the volume",
              "items" => [
                { "title" => "Local methods", "body" => "Twelve new rails. Most of them requested by a single market." },
                { "title" => "Radar 4", "body" => "Fraud held flat while volume grew. The model is in the report." },
                { "title" => "Connect", "body" => "Platforms paid out to 2.1 million connected accounts, on time." },
                { "title" => "Climate", "body" => "We bought removals for the year's compute. The registry links are public." }
              ],
              "align" => "start",
              "surface" => "muted"
            }
          },
          {
            "type" => "quote",
            "props" => {
              "quote" => "If the number needs a footnote to be true, take the number off the page.",
              "attribution" => "CFO note",
              "role" => "Inside the report cover",
              "surface" => "contrast"
            }
          },
          {
            "type" => "cta_split",
            "props" => {
              "kicker" => "The report",
              "headline" => "Forty pages. The same numbers as the board deck.",
              "body" => "PDF, a data sheet, and the post-mortems. We will not make you give an email for the file.",
              "primary_label" => "Download the report",
              "primary_href" => "https://example.com/report",
              "secondary_label" => "Talk to sales",
              "secondary_href" => "contact",
              "image_side" => "right"
            }
          }
        ]
      },
      {
        "key" => "why_us",
        "sections" => [
          {
            "type" => "hero_split",
            "props" => {
              "eyebrow" => "Why teams stay",
              "headline" => "Email that looks like you, and a list you can actually trust",
              "subhead" => "Templates you will edit, automation you can explain to finance, and a deliverability team that answers the phone.",
              "primary_label" => "Start a trial",
              "primary_href" => "https://example.com/start",
              "secondary_label" => "See a sample send",
              "secondary_href" => "about"
            }
          },
          {
            "type" => "split_checklist",
            "props" => {
              "kicker" => "The switch",
              "heading" => "What you get that the last tool kept promising",
              "body" => "A list that stays clean, a send that lands, and reports a marketer can read without a dashboard tour.",
              "button_label" => "Compare plans",
              "button_href" => "https://example.com/pricing",
              "items" => [
                { "title" => "A builder that does not fight the brand", "body" => "Your type, your colour, a footer that already has the address." },
                { "title" => "Automation you can draw on a napkin", "body" => "Welcome, win-back, a birthday. Branching without a certification." },
                { "title" => "Deliverability with a name attached", "body" => "A person who will look at your domain, not a help article." },
                { "title" => "A list that unsubscribes itself", "body" => "One click, every send, and a suppression you cannot accidentally wipe." },
                { "title" => "Reports that match the inbox", "body" => "Opens you can defend, clicks that are not bots, revenue if you pass it in." },
                { "title" => "Roles that fit a Friday", "body" => "An intern who can draft. A lead who can send. No one who can delete the list." }
              ],
              "surface" => "muted"
            }
          },
          {
            "type" => "metrics",
            "props" => {
              "kicker" => "After the move",
              "heading" => "What customers measured in the first quarter",
              "items" => [
                { "value" => "14 days", "label" => "median time to first send", "body" => "Including the DNS afternoon. We sit on the call." },
                { "value" => "+18%", "label" => "inbox placement", "body" => "Against the previous tool, on the same domain, same list." },
                { "value" => "2.1×", "label" => "automated revenue", "body" => "Welcome and win-back, turned on, left alone." },
                { "value" => "11 min", "label" => "to get a human", "body" => "Chat, then a person who has sent a million emails." }
              ],
              "align" => "center"
            }
          },
          {
            "type" => "testimonials",
            "props" => {
              "heading" => "From teams who already switched",
              "items" => [
                { "quote" => "We stopped arguing about the builder. The email looks like the site. That was the whole brief.", "name" => "Maya Chen", "role" => "Brand, Halcyon" },
                { "quote" => "Deliverability stopped being a weekly incident. I have their number in my phone.", "name" => "Daniel Osei", "role" => "Lifecycle, Vertex" },
                { "quote" => "Finance finally understands the report. I no longer export a CSV to prove a click.", "name" => "Sara Lindqvist", "role" => "Growth, Oakline" }
              ],
              "surface" => "muted",
              "align" => "center"
            }
          },
          {
            "type" => "faq",
            "props" => {
              "heading" => "Before you move the list",
              "items" => [
                { "question" => "Will you import the last three years?", "answer" => "Yes — subscribers, tags, the unsubscribes. We will not re-permission people who already said no." },
                { "question" => "Do you keep our sending domain?", "answer" => "Yes. We help you move the records on a call. The old tool can keep sending until you cut over." },
                { "question" => "What if we hate it in week two?", "answer" => "Export everything, including suppression. We will not hold the list hostage." }
              ]
            }
          },
          {
            "type" => "cta_band",
            "props" => {
              "headline" => "Bring the list. We will sit on the DNS call.",
              "body" => "Fourteen days, the full product, a person if you want one. No card until you keep it.",
              "button_label" => "Start a trial",
              "button_href" => "https://example.com/start"
            }
          }
        ]
      },
      {
        "key" => "launch_note",
        "sections" => [
          {
            "type" => "announcement",
            "props" => {
              "badge" => "Shipping now",
              "body" => "Edge Functions 2 — a runtime that boots in 0.3 ms and talks to your database without a tunnel.",
              "link_label" => "Read the note",
              "href" => "https://example.com/blog",
              "surface" => "accent"
            }
          },
          {
            "type" => "product_spotlight",
            "props" => {
              "kicker" => "Edge Functions 2",
              "headline" => "Compute that lives next to the request",
              "subhead" => "Write a function, git push, it runs in the region the visitor is already in. No containers to keep warm. No tunnel to your database.",
              "primary_label" => "Deploy a function",
              "primary_href" => "https://example.com/start",
              "secondary_label" => "Read the docs",
              "secondary_href" => "https://example.com/docs",
              "specs" => [
                { "value" => "0.3 ms", "label" => "cold start, p50" },
                { "value" => "31", "label" => "regions, same runtime" },
                { "value" => "10s", "label" => "CPU budget, default" },
                { "value" => "0", "label" => "servers you manage" }
              ],
              "spacing" => "roomy"
            }
          },
          {
            "type" => "feature_tabs",
            "props" => {
              "kicker" => "In the note",
              "heading" => "What changed, and why it is safe to try on Friday",
              "tabs" => [
                { "label" => "Runtime", "title" => "A boot you will not notice", "body" => "0.3 ms to first instruction. The old 40 ms tax is gone. Streaming starts with the first byte." },
                { "label" => "Data", "title" => "Your database, no tunnel", "body" => "A connector that lives in the same region as the write. Prepared statements, pooling, the boring parts done." },
                { "label" => "Preview", "title" => "Every branch gets the function", "body" => "The pull request URL runs the new runtime. Comments land on the preview, not in Slack archaeology." },
                { "label" => "Observability", "title" => "Logs with the deploy that caused them", "body" => "Traces, a flame, the region. Rollback is the previous immutable build." }
              ],
              "align" => "start"
            }
          },
          {
            "type" => "metrics",
            "props" => {
              "kicker" => "Design partners",
              "heading" => "The first thirty days on 2",
              "items" => [
                { "value" => "−62%", "label" => "p95 origin time", "body" => "Against Functions 1, same routes, same week of traffic." },
                { "value" => "4.1M", "label" => "invocations / day", "body" => "Across the twelve teams who moved first." },
                { "value" => "0", "label" => "SEV-1s attributed", "body" => "We kept the old runtime on a flag for a week. Nobody flipped back." },
                { "value" => "11 min", "label" => "median migrate", "body" => "Change the runtime key. Ship. The rest is config you already had." }
              ],
              "align" => "center",
              "surface" => "muted"
            }
          },
          {
            "type" => "logo_cloud",
            "props" => {
              "heading" => "Already running 2 in production",
              "items" => [
                { "name" => "Halcyon" },
                { "name" => "Vertex" },
                { "name" => "Oakline" },
                { "name" => "Parallel" },
                { "name" => "Monolith" }
              ],
              "spacing" => "tight"
            }
          },
          {
            "type" => "cta_split",
            "props" => {
              "kicker" => "Try it on a preview",
              "headline" => "Flip one project. Keep the rest on 1 until you are sure.",
              "body" => "The runtime is a project setting. Roll forward, roll back. Billing does not change until the function actually runs.",
              "primary_label" => "Upgrade a project",
              "primary_href" => "https://example.com/start",
              "secondary_label" => "Read the changelog",
              "secondary_href" => "https://example.com/blog",
              "image_side" => "right"
            }
          }
        ]
      }
    ].freeze

    module_function

    def sync!
      ensure_layouts!
      ensure_skeletons!
    end

    # Overwrites every platform layout and skeleton row with its code seed,
    # discarding owner edits to those rows. Tenant websites are untouched.
    def refresh!
      ensure_layouts!(refresh: true)
      ensure_skeletons!(refresh: true)
    end

    def layout_for(key)
      sync_if_needed
      WebsiteLayout.active.find_by(key: key.to_s)
    end

    def skeleton_for(key)
      sync_if_needed
      WebsiteSkeleton.active.find_by(key: key.to_s)
    end

    def layouts
      sync_if_needed
      WebsiteLayout.active.to_a
    end

    def skeletons
      sync_if_needed
      WebsiteSkeleton.active.to_a
    end

    def known_skeleton?(key)
      return false if key.blank?

      WebsiteSkeleton.active.exists?(key: key.to_s) || Websites::Skeletons::KEYS.include?(key.to_s)
    end

    def known_layout?(key)
      return false if key.blank?

      WebsiteLayout.active.exists?(key: key.to_s)
    end

    def infer_layout_key(sections)
      types = Array(sections).map { |raw|
        hash = raw.respond_to?(:to_h) ? raw.to_h.stringify_keys : {}
        hash["type"].to_s
      }
      return if types.empty?

      layouts.find { |layout|
        Array(layout.sections).map { |raw|
          hash = raw.respond_to?(:stringify_keys) ? raw.stringify_keys : {}
          hash["type"].to_s
        } == types
      }&.key
    end

    def sync_if_needed
      return if defined?(@synced) && @synced
      return unless website_tables_ready?

      sync!
      @synced = true
    end

    def reset_sync_flag!
      @synced = false
    end

    def website_tables_ready?
      WebsiteLayout.table_exists? && WebsiteSkeleton.table_exists?
    rescue ActiveRecord::StatementInvalid
      false
    end

    def ensure_layouts!(refresh: false)
      position = 0
      seed_layout_pages.each do |page|
        key = page["layout_key"].to_s
        next if key.blank?

        position += 1
        upsert_layout!(
          key: key,
          sections: page["sections"],
          position: position,
          refresh: refresh
        )
      end

      EXTRA_LAYOUTS.each do |spec|
        position += 1
        upsert_layout!(
          key: spec["key"],
          sections: spec["sections"],
          position: position,
          refresh: refresh
        )
      end

      fill_page_media!
    end

    def ensure_skeletons!(refresh: false)
      Websites::Skeletons::KEYS.each_with_index do |key, index|
        row = WebsiteSkeleton.find_or_initialize_by(key: key)
        seed_pages = Websites::Media.fill_pages(Websites::Skeletons.seed_pages_for(key), key)
        if row.persisted? && !refresh
          row.pages = Websites::Media.fill_pages(row.pages, key)
          row.save! if row.changed?
        else
          row.name = english_skeleton_name(key)
          row.description = english_skeleton_description(key)
          row.pages = seed_pages
          row.position = index
          row.theme_key = nil
          row.save!
        end
      end
    end

    def upsert_layout!(key:, sections:, position:, refresh: false)
      row = WebsiteLayout.find_or_initialize_by(key: key)
      keep = row.persisted? && !refresh
      filled = Websites::Skeletons.decorate_sections(keep ? row.sections : sections, key)
      if keep
        row.sections = filled
        row.save! if row.changed?
        return
      end

      row.name = english_layout_name(key)
      row.description = english_layout_description(key)
      row.sections = filled
      row.position = position
      row.theme_key = nil
      row.save!
    end

    def fill_page_media!
      return unless WebsitePage.table_exists?

      WebsitePage.find_each do |page|
        filled = Websites::Media.fill_sections(page.sections, page.layout_key.to_s.split("_").first)
        next if page.sections == filled

        page.update_columns(sections: filled)
      end
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def seed_layout_pages
      Websites::Skeletons::KEYS.flat_map { |key| Websites::Skeletons.seed_pages_for(key) }
    end

    def english_layout_name(key)
      translate_en("website.layouts.#{key}.name") || key.to_s
    end

    def english_layout_description(key)
      translate_en("website.layouts.#{key}.description")
    end

    def english_skeleton_name(key)
      translate_en("website.skeletons.#{key}.name") || key.to_s
    end

    def english_skeleton_description(key)
      translate_en("website.skeletons.#{key}.description")
    end

    def translate_en(key)
      return unless I18n.exists?(key, locale: :en)

      I18n.t(key, locale: :en)
    end
  end
end
