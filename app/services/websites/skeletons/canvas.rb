# frozen_string_literal: true

module Websites
  module Skeletons
    # Figma register: a multiplayer design product — one infinite file,
    # live cursors, a library, and a pricing page that reads like a tool.
    module Canvas
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "canvas_home",
          "sections" => [
            {
              "type" => "announcement",
              "props" => {
                "badge" => "New",
                "body" => "Canvas 4 is out — variables, branching and a comment that finally sticks to the layer.",
                "link_label" => "See what's new",
                "href" => "product",
                "surface" => "accent"
              }
            },
            {
              "type" => "product_spotlight",
              "props" => {
                "kicker" => "Design, together",
                "headline" => "The file everyone can open at once",
                "subhead" => "Sketch on the same page. Leave a note on the exact frame. Ship a library the whole company can reuse on Monday.",
                "primary_label" => "Start a file",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "Watch a 90-second tour",
                "secondary_href" => "product",
                "specs" => [
                  { "value" => "60 fps", "label" => "on files with 10,000 layers" },
                  { "value" => "<40 ms", "label" => "cursor latency, worldwide" },
                  { "value" => "∞", "label" => "pages in a single file" },
                  { "value" => "SSO", "label" => "on every paid seat" }
                ],
                "spacing" => "roomy"
              }
            },
            {
              "type" => "logo_cloud",
              "props" => {
                "heading" => "The teams that design the products you already use",
                "items" => [
                  { "name" => "Halcyon" },
                  { "name" => "Northwind" },
                  { "name" => "Vertex" },
                  { "name" => "Oakline" },
                  { "name" => "Parallel" },
                  { "name" => "Monolith" }
                ],
                "spacing" => "tight"
              }
            },
            {
              "type" => "metrics",
              "props" => {
                "kicker" => "In production",
                "heading" => "Built for the file that never closes",
                "subhead" => "Numbers from the last thirty days, not a launch deck.",
                "items" => [
                  { "value" => "4.2M", "label" => "files opened", "body" => "Across 190 countries, most of them with more than one cursor inside." },
                  { "value" => "38k", "label" => "published libraries", "body" => "Tokens, components and recipes shared beyond a single team." },
                  { "value" => "12 min", "label" => "median time to first comment", "body" => "From invite sent to a note sitting on the right frame." },
                  { "value" => "99.99%", "label" => "file uptime", "body" => "The canvas stays up when a teammate is mid-sentence." }
                ],
                "align" => "center",
                "surface" => "muted"
              }
            },
            {
              "type" => "feature_tabs",
              "props" => {
                "kicker" => "The product",
                "heading" => "One tool from first sketch to handoff",
                "subhead" => "Design, prototype, annotate and publish without exporting a single PNG.",
                "tabs" => [
                  { "label" => "Design", "title" => "A page that feels like paper and acts like software", "body" => "Frames, auto-layout and variables live in the same file. Zoom to a pixel or to the whole product." },
                  { "label" => "Prototype", "title" => "Flows you can click, not slides you narrate", "body" => "Connect frames, add a spring, and send a link. Reviewers tap through the real path." },
                  { "label" => "Library", "title" => "A system that updates itself", "body" => "Publish a component once. Every file that uses it picks up the change — or stays pinned, on purpose." },
                  { "label" => "Handoff", "title" => "Inspect without a second app", "body" => "Spacing, tokens and exports sit on the layer. Engineering copies what they need and leaves a thread if they cannot." }
                ],
                "align" => "start",
                "spacing" => "roomy"
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "kicker" => "Studios",
                "heading" => "What design leads say after the first month",
                "items" => [
                  { "quote" => "We stopped mailing ZIPs. The file is the source of truth, and the comments live on it.", "name" => "Maya Chen", "role" => "Design Director, Halcyon" },
                  { "quote" => "Our system used to drift the week after we published it. Libraries closed that gap.", "name" => "Daniel Osei", "role" => "Principal Designer, Vertex" },
                  { "quote" => "I can sit in a review from another timezone and still point at the exact layer.", "name" => "Sara Lindqvist", "role" => "Head of Design, Oakline" }
                ],
                "surface" => "muted",
                "align" => "center"
              }
            },
            {
              "type" => "cta_split",
              "props" => {
                "kicker" => "Start free",
                "headline" => "Open a file before you decide",
                "body" => "Three seats, unlimited personal files, no card. Invite the rest of the team when the first project lands.",
                "primary_label" => "Create a file",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "Compare plans",
                "secondary_href" => "pricing",
                "image_side" => "right"
              }
            }
          ]
        },
        {
          "title" => "Product",
          "slug" => "product",
          "home" => false,
          "nav_visible" => true,
          "role" => "product",
          "layout_key" => "canvas_product",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Canvas 4",
                "headline" => "Everything that used to live in five tools",
                "subhead" => "A shared canvas, a living library, prototypes you can tap, and a comment that knows which layer you meant.",
                "primary_label" => "Start designing",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "See pricing",
                "secondary_href" => "pricing"
              }
            },
            {
              "type" => "feature_tabs",
              "props" => {
                "kicker" => "Workflow",
                "heading" => "How a file actually moves",
                "subhead" => "From a blank page on Monday to a published library on Friday.",
                "tabs" => [
                  { "label" => "Explore", "title" => "Think in pages, not artboards", "body" => "Dump research, sketches and a messy first pass on adjacent pages. Nothing is precious until you say it is." },
                  { "label" => "Build", "title" => "Layout that holds when the copy changes", "body" => "Auto-layout, min/max and variables keep a card honest when someone writes a longer sentence." },
                  { "label" => "Review", "title" => "Comments that refuse to float", "body" => "Pin a note to a layer. It travels with the component, even after a rename." },
                  { "label" => "Ship", "title" => "A branch you can merge", "body" => "Try the risky version on a branch. Merge when the room agrees — or keep it as a record of the attempt." }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "split_checklist",
              "props" => {
                "kicker" => "For growing teams",
                "heading" => "The things that used to break at twenty people",
                "body" => "Permissions, libraries and a paper trail — without turning the file into a ticket queue.",
                "button_label" => "Talk to us",
                "button_href" => "contact",
                "items" => [
                  { "title" => "Spaces, not shared passwords", "body" => "A space per brand or product. Guests see only the files you invite them to." },
                  { "title" => "Branching that designers will use", "body" => "Name the experiment, compare, merge. No Git lecture required." },
                  { "title" => "A library with owners", "body" => "Publish rights sit with the system team. Everyone else consumes." },
                  { "title" => "An audit you can export", "body" => "Who published, who restored, who shared a link. Finance already asked." },
                  { "title" => "SSO and SCIM", "body" => "Seats appear and disappear with the directory. No leftover editors." }
                ],
                "surface" => "contrast"
              }
            },
            {
              "type" => "alternating_features",
              "props" => {
                "kicker" => "In the file",
                "heading" => "Details that keep a team in one place",
                "items" => [
                  { "title" => "Multiplayer that stays out of the way", "body" => "Cursors, selections and a follow mode. The canvas does not stutter when twelve people zoom at once." },
                  { "title" => "Variables for colour, type and space", "body" => "Swap a theme, a density or a locale without rebuilding the page." },
                  { "title" => "Dev Mode that engineers actually open", "body" => "Tokens, spacing and a copy button. No plugin tax, no second window." }
                ]
              }
            },
            {
              "type" => "collection_rail",
              "props" => {
                "kicker" => "Templates",
                "heading" => "Start from a file that already knows the job",
                "subhead" => "Product UI, a workshop, a brand kit — duplicate and make it yours.",
                "aspect" => "landscape",
                "items" => [
                  { "title" => "Mobile app kit", "meta" => "214 components", "href" => "product" },
                  { "title" => "Design system starter", "meta" => "Tokens + recipes", "href" => "product" },
                  { "title" => "Workshop board", "meta" => "For the Monday room", "href" => "product" },
                  { "title" => "Marketing site", "meta" => "12 sections", "href" => "product" },
                  { "title" => "Handoff cover", "meta" => "For engineering", "href" => "product" },
                  { "title" => "Research wall", "meta" => "Quotes and clips", "href" => "product" }
                ],
                "align" => "start",
                "surface" => "muted"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Bring the next project into one file",
                "body" => "Import a sketch, invite two people, and see if the room gets quieter.",
                "button_label" => "Start free",
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
          "layout_key" => "canvas_pricing",
          "sections" => [
            {
              "type" => "hero_centered",
              "props" => {
                "eyebrow" => "Pricing",
                "headline" => "Pay for seats, not for files",
                "subhead" => "Personal files stay free. Shared workspaces start when the team does. Annual billing saves two months.",
                "primary_label" => "Start free",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "Talk to sales",
                "secondary_href" => "contact",
                "media_mode" => "none"
              }
            },
            {
              "type" => "pricing",
              "props" => {
                "kicker" => "Plans",
                "heading" => "Simple seats",
                "subhead" => "Every plan includes the canvas, prototypes and comments. Libraries and SSO land on Professional.",
                "featured_label" => "Most teams",
                "tiers" => [
                  {
                    "name" => "Starter",
                    "price" => "$0",
                    "cadence" => "forever",
                    "body" => "For the file you keep to yourself.",
                    "features" => "3 files in a workspace\nUnlimited personal drafts\nCommunity templates",
                    "button_label" => "Start free",
                    "button_href" => "https://example.com/start",
                    "highlight" => "standard"
                  },
                  {
                    "name" => "Professional",
                    "price" => "$15",
                    "cadence" => "per editor / month",
                    "body" => "For product and brand teams.",
                    "features" => "Unlimited shared files\nTeam libraries\nBranching and version history\nPriority support",
                    "button_label" => "Start a trial",
                    "button_href" => "https://example.com/start",
                    "highlight" => "featured"
                  },
                  {
                    "name" => "Organization",
                    "price" => "$45",
                    "cadence" => "per editor / month",
                    "body" => "For companies with more than one brand.",
                    "features" => "Everything in Professional\nSSO, SCIM and audit log\nShared fonts and org libraries\nDedicated success",
                    "button_label" => "Contact sales",
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
                "kicker" => "Compare",
                "heading" => "What each plan unlocks",
                "column_1" => "Starter",
                "column_2" => "Professional",
                "column_3" => "Organization",
                "rows" => [
                  { "title" => "Shared files", "value_1" => "3", "value_2" => "Unlimited", "value_3" => "Unlimited" },
                  { "title" => "Team libraries", "value_1" => "—", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "Branching", "value_1" => "—", "value_2" => "✓", "value_3" => "✓" },
                  { "title" => "SSO and SCIM", "value_1" => "—", "value_2" => "—", "value_3" => "✓" },
                  { "title" => "Audit log", "value_1" => "—", "value_2" => "—", "value_3" => "✓" },
                  { "title" => "Guest editors", "value_1" => "2", "value_2" => "Unlimited", "value_3" => "Unlimited" }
                ],
                "surface" => "muted",
                "align" => "start"
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "Before you pick a plan",
                "items" => [
                  { "question" => "Do viewers cost a seat?", "answer" => "No. Anyone with a link can inspect and comment. You pay for people who edit." },
                  { "question" => "Can I start on Starter and move later?", "answer" => "Yes. Upgrade in place. Files, comments and libraries come with you." },
                  { "question" => "What happens if someone leaves?", "answer" => "Their seat frees at the end of the month. Their work stays in the space." }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Still deciding between Professional and Organization?",
                "body" => "Tell us how many brands and how you sign people in. We will recommend one plan.",
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
          "layout_key" => "canvas_about",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "About Canvas",
                "headline" => "We are building the file the whole company can stand in.",
                "body" => "Design used to live on one person's machine. We started Canvas so a decision could happen on the page, with everyone looking at the same layer."
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "kicker" => "Studio",
                "heading" => "A small team that still ships weekly",
                "people" => [
                  { "name" => "Elena Voss", "role" => "Founder", "bio" => "Spent a decade watching files fork the night before a launch." },
                  { "name" => "Kenji Mori", "role" => "Design", "bio" => "Keeps the canvas quiet enough that you forget it is software." },
                  { "name" => "Amina Diallo", "role" => "Engineering", "bio" => "Obsessed with the forty milliseconds between two cursors." },
                  { "name" => "Noah Pell", "role" => "Libraries", "bio" => "Thinks a published component is a promise, not a suggestion." }
                ],
                "align" => "start",
                "surface" => "muted"
              }
            },
            {
              "type" => "timeline",
              "props" => {
                "kicker" => "Milestones",
                "heading" => "How the file grew up",
                "items" => [
                  { "date" => "2018", "title" => "A blank page in a rented room", "body" => "Two people, one infinite canvas, and a refusal to export." },
                  { "date" => "2020", "title" => "Libraries", "body" => "The first published component updated a hundred files overnight." },
                  { "date" => "2023", "title" => "Branching", "body" => "Designers got a way to try the dangerous idea without copying the file." },
                  { "date" => "2026", "title" => "Canvas 4", "body" => "Variables, comments that stick, and a file that still opens in one tab." }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "If the file needs a meeting to be understood, the file is not finished.",
                "attribution" => "Elena Voss",
                "role" => "On the studio wall",
                "surface" => "contrast"
              }
            },
            {
              "type" => "cta_split",
              "props" => {
                "kicker" => "Work with us",
                "headline" => "We hire people who care about the layer",
                "body" => "Design, engineering and the unglamorous work of keeping a library honest. Offices in Lisbon and Oakland.",
                "primary_label" => "See open roles",
                "primary_href" => "https://example.com/careers",
                "secondary_label" => "Write to us",
                "secondary_href" => "contact",
                "image_side" => "left"
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
          "layout_key" => "canvas_contact",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Talk to a person who has opened a 10,000-layer file",
                "address" => "440 Market Street\nSan Francisco, CA",
                "email" => "hello@example.com",
                "phone" => "+1 415 555 0140",
                "hours" => "Monday–Friday, 9:00–18:00 PT"
              }
            },
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Studios",
                "heading" => "Walk in, or book a workspace tour",
                "subhead" => "We will sit you in a live file and let the product do the talking.",
                "places" => [
                  { "name" => "Market Street", "address" => "440 Market Street\nSan Francisco, CA", "hours" => "Weekdays 9:00–18:00", "phone" => "+1 415 555 0140", "button_label" => "Book a tour", "button_href" => "https://example.com/tour" },
                  { "name" => "Chiado", "address" => "18 Rua Garrett\nLisbon", "hours" => "Weekdays 10:00–19:00", "phone" => "+351 21 555 0100", "button_label" => "Book a tour", "button_href" => "https://example.com/tour" }
                ],
                "surface" => "muted"
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "Before you write",
                "items" => [
                  { "question" => "Can we migrate an existing library?", "answer" => "Yes. We have a guided import for common file formats and a concierge for the messy ones." },
                  { "question" => "Do you sign BAAs and DPAs?", "answer" => "On Organization. Send the paper to legal@example.com and we will turn it around in a week." }
                ]
              }
            }
          ]
        }
      ].freeze
    end
  end
end
