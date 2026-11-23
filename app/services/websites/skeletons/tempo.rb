# frozen_string_literal: true

module Websites
  module Skeletons
    # Spotify register: audio streaming, dark and bold — playlists as
    # the product, artists as the culture, a home that wants the volume up.
    module Tempo
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "tempo_home",
          "sections" => [
            {
              "type" => "announcement",
              "props" => {
                "badge" => "Live",
                "body" => "Night Shift — a three-hour radio from Lagos, in your evening, wherever you are.",
                "link_label" => "Press play",
                "href" => "listen",
                "surface" => "accent"
              }
            },
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Tempo",
                "headline" => "The soundtrack that already knows the room",
                "subhead" => "Ninety million tracks, radio that still has a host, and playlists built by people who listen for a living.",
                "primary_label" => "Get Tempo Free",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "See what's playing",
                "secondary_href" => "listen",
                "tone" => "dark"
              }
            },
            {
              "type" => "collection_rail",
              "props" => {
                "kicker" => "Today",
                "heading" => "Playlists the building is actually in",
                "subhead" => "Updated this morning. Skip what you like. We will remember.",
                "aspect" => "square",
                "items" => [
                  { "title" => "Night Shift", "meta" => "Radio · Lagos", "href" => "listen" },
                  { "title" => "Kitchen after ten", "meta" => "62 tracks", "href" => "listen" },
                  { "title" => "First train", "meta" => "Daily mix", "href" => "listen" },
                  { "title" => "Left speaker", "meta" => "New: electronic", "href" => "listen" },
                  { "title" => "Soft launch", "meta" => "Indie · 48 tracks", "href" => "listen" },
                  { "title" => "Heavy coat", "meta" => "Soul · winter", "href" => "listen" },
                  { "title" => "Desk, headphones", "meta" => "Focus · no lyrics", "href" => "listen" },
                  { "title" => "Friday service", "meta" => "Gospel · live", "href" => "listen" }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "metrics",
              "props" => {
                "kicker" => "This week",
                "heading" => "The catalog, in motion",
                "items" => [
                  { "value" => "90M", "label" => "tracks", "body" => "From a phone demo in Accra to a session that closed last night." },
                  { "value" => "184", "label" => "markets", "body" => "Local charts, local hosts, the same app." },
                  { "value" => "12k", "label" => "hours of radio a week", "body" => "People talking between records. On purpose." },
                  { "value" => "4", "label" => "free skips an hour", "body" => "Or none, if you like the host. Premium removes the cap." }
                ],
                "align" => "center",
                "surface" => "contrast"
              }
            },
            {
              "type" => "feature_tabs",
              "props" => {
                "kicker" => "How it plays",
                "heading" => "Made for the way a day actually sounds",
                "tabs" => [
                  { "label" => "Playlists", "title" => "Built by listeners, not a mood word", "body" => "Editors still have names. A playlist can argue with the algorithm, and often wins." },
                  { "label" => "Radio", "title" => "A host, a clock, a city", "body" => "Night Shift from Lagos. Morning Service from Atlanta. You can join late." },
                  { "label" => "Live", "title" => "The room, from the cheap seats", "body" => "Sessions, tiny desks, a festival feed when you cannot be there." },
                  { "label" => "Yours", "title" => "A library that does not reshuffle itself", "body" => "Liked songs stay liked. Downloads stay yours on a plane." }
                ],
                "align" => "start",
                "spacing" => "roomy"
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "kicker" => "In the culture",
                "heading" => "Artists, hosts, and the people who press play first",
                "items" => [
                  { "quote" => "They put the record on Night Shift before the label had a plan. That is still how people find me.", "name" => "Kemi Ade", "role" => "Artist, Lagos" },
                  { "quote" => "The host talks like a friend who got there early. I stay for the talk as much as the track.", "name" => "Joel Hart", "role" => "Listener, Chicago" },
                  { "quote" => "We cleared a live session in four days. The clip outran the single.", "name" => "Rina Cho", "role" => "Manager" }
                ],
                "surface" => "muted",
                "align" => "center"
              }
            },
            {
              "type" => "cta_split",
              "props" => {
                "kicker" => "Tempo Premium",
                "headline" => "No ads. Offline. The skip is yours.",
                "body" => "$10.99 a month, or $5.99 for students. A family plan covers six. Free still plays — just with a host in the breaks.",
                "primary_label" => "Go Premium",
                "primary_href" => "https://example.com/premium",
                "secondary_label" => "Keep listening free",
                "secondary_href" => "https://example.com/start",
                "image_side" => "right"
              }
            }
          ]
        },
        {
          "title" => "Listen",
          "slug" => "listen",
          "home" => false,
          "nav_visible" => true,
          "role" => "listen",
          "layout_key" => "tempo_listen",
          "sections" => [
            {
              "type" => "collection_rail",
              "props" => {
                "kicker" => "Charts",
                "heading" => "What the cities are playing",
                "subhead" => "Updated every Friday. Local first, then the rest of the map.",
                "aspect" => "square",
                "items" => [
                  { "title" => "Lagos Top 50", "meta" => "This week", "href" => "listen" },
                  { "title" => "Seoul After Dark", "meta" => "Editorial", "href" => "listen" },
                  { "title" => "São Paulo Heat", "meta" => "Chart", "href" => "listen" },
                  { "title" => "London Late", "meta" => "Radio", "href" => "listen" },
                  { "title" => "Mexico City Sun", "meta" => "Editorial", "href" => "listen" },
                  { "title" => "Berlin Basement", "meta" => "New", "href" => "listen" },
                  { "title" => "Nashville Morning", "meta" => "Country", "href" => "listen" }
                ]
              }
            },
            {
              "type" => "image_banner",
              "props" => {
                "kicker" => "Sessions",
                "headline" => "One room. One take. No audience except you.",
                "body" => "This month: a piano in Accra, a drum kit in Mexico City, a voice and a hallway in Oslo.",
                "button_label" => "Watch the sessions",
                "button_href" => "https://example.com/sessions",
                "height" => "tall",
                "placement" => "bottom"
              }
            },
            {
              "type" => "feature_tabs",
              "props" => {
                "kicker" => "Radio",
                "heading" => "Shows with a clock and a point of view",
                "tabs" => [
                  { "label" => "Night Shift", "title" => "Lagos, 22:00, three hours", "body" => "New records, old records, and a host who will tell you why the bridge matters." },
                  { "label" => "Morning Service", "title" => "Atlanta, 7:00", "body" => "Gospel that does not wait for Sunday, and a weather report you can dance to." },
                  { "label" => "Left Speaker", "title" => "Berlin, midweek", "body" => "Electronic that still has a human in it. Guests bring a crate." },
                  { "label" => "Soft Launch", "title" => "The first play", "body" => "A new artist, a full record, no skip button for the first twenty minutes. On purpose." }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "gallery",
              "props" => {
                "kicker" => "On set",
                "heading" => "This month's rooms",
                "items" => [
                  { "caption" => "Accra piano" },
                  { "caption" => "Mexico City kit" },
                  { "caption" => "Oslo hallway" },
                  { "caption" => "Night Shift desk" }
                ],
                "surface" => "muted"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Follow a show. It will find you tomorrow.",
                "body" => "Free accounts keep the library. Premium keeps the skip and the downloads.",
                "button_label" => "Open Tempo",
                "button_href" => "https://example.com/start"
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
          "layout_key" => "tempo_stories",
          "sections" => [
            {
              "type" => "story_index",
              "props" => {
                "kicker" => "Culture",
                "heading" => "How a record leaves the room",
                "stories" => [
                  { "kicker" => "Cover", "title" => "Kemi Ade's night that would not end", "body" => "A single, a session, and the week Night Shift would not stop playing it.", "byline" => "12 min", "href" => "stories" },
                  { "kicker" => "Radio", "title" => "Why we still hire hosts", "byline" => "Essay", "href" => "stories" },
                  { "kicker" => "City", "title" => "A week in the Seoul after-dark chart", "byline" => "8 min", "href" => "stories" },
                  { "kicker" => "Session", "title" => "The hallway in Oslo", "byline" => "Video", "href" => "listen" },
                  { "kicker" => "Industry", "title" => "Paying the people on the record", "byline" => "6 min", "href" => "about" },
                  { "kicker" => "Playlist", "title" => "How Kitchen after ten gets made", "byline" => "5 min", "href" => "listen" }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "A playlist is an argument. If it cannot be wrong, it cannot be good.",
                "attribution" => "Idris Cole",
                "role" => "Head of Editorial",
                "surface" => "contrast"
              }
            },
            {
              "type" => "card_grid",
              "props" => {
                "kicker" => "More",
                "heading" => "From the desk",
                "cards" => [
                  { "title" => "The year in 50 tracks", "body" => "Not a ranking. A listening copy of the year.", "href" => "stories" },
                  { "title" => "How we pay out", "body" => "A statement an artist can read without a lawyer.", "href" => "about" },
                  { "title" => "Submit a session room", "body" => "If the room is good, we will bring a kit.", "href" => "contact" }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Get the Sunday letter",
                "body" => "Five tracks, one argument, no playlist dump. One email.",
                "button_label" => "Subscribe",
                "button_href" => "https://example.com/letter"
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
          "layout_key" => "tempo_about",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "About Tempo",
                "headline" => "We work for the next play, and for the person who made the record.",
                "body" => "A catalog this large is a privilege. The job is to put the right song in the room — and to send the money back to the room it came from."
              }
            },
            {
              "type" => "metrics",
              "props" => {
                "heading" => "Last year, paid out",
                "items" => [
                  { "value" => "$2.4B", "label" => "to rights holders", "body" => "Labels, publishers, the person who wrote the bridge." },
                  { "value" => "48%", "label" => "of streams from outside the top 10k", "body" => "The catalog is not a hit factory. Discovery still works." },
                  { "value" => "11k", "label" => "artists on a living wage from Tempo alone", "body" => "Our threshold, published, audited." },
                  { "value" => "184", "label" => "markets with a local editor", "body" => "Not a translated homepage. A person with a crate." }
                ],
                "align" => "center",
                "surface" => "contrast"
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "kicker" => "The desk",
                "heading" => "Editors, hosts, the people who still argue",
                "people" => [
                  { "name" => "Idris Cole", "role" => "Editorial", "bio" => "Thinks a playlist without a point of view is just a folder." },
                  { "name" => "Amara Nwosu", "role" => "Night Shift", "bio" => "Hosts from Lagos. Will talk over the intro if the story is better." },
                  { "name" => "Pavel Hrdlicka", "role" => "Sessions", "bio" => "Finds the rooms. Packs the kit." },
                  { "name" => "Sonia Reyes", "role" => "Payouts", "bio" => "Writes the statements artists can actually read." }
                ],
                "surface" => "muted"
              }
            },
            {
              "type" => "cta_split",
              "props" => {
                "kicker" => "Work with us",
                "headline" => "Artists, labels, a room we should know about",
                "body" => "Pitch a record, a session, or a city we are late to. A person reads the inbox.",
                "primary_label" => "Write to the desk",
                "primary_href" => "contact",
                "secondary_label" => "Open Tempo",
                "secondary_href" => "https://example.com/start",
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
          "layout_key" => "tempo_contact",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "The desk reads the inbox",
                "address" => "14 Hornsgatan\nStockholm",
                "email" => "desk@example.com",
                "phone" => "+46 8 555 010",
                "hours" => "Weekdays, 10:00–18:00 CET"
              }
            },
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Rooms",
                "heading" => "Studios and the radio floor",
                "subhead" => "Pitch a session, a show, or a city we are late to.",
                "places" => [
                  { "name" => "Stockholm", "address" => "14 Hornsgatan\nStockholm", "hours" => "Weekdays 10:00–18:00", "phone" => "+46 8 555 010", "button_label" => "Write to the desk", "button_href" => "https://example.com/desk" },
                  { "name" => "Lagos", "address" => "8 Adeola Odeku\nVictoria Island", "hours" => "Night Shift 20:00–01:00", "phone" => "+234 1 555 0188", "button_label" => "Pitch Night Shift", "button_href" => "https://example.com/desk" },
                  { "name" => "Los Angeles", "address" => "7100 Santa Monica Boulevard\nWest Hollywood, CA", "hours" => "Weekdays 11:00–19:00", "phone" => "+1 323 555 0144", "button_label" => "Book a session", "button_href" => "https://example.com/sessions" }
                ],
                "surface" => "muted"
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "Before you write",
                "items" => [
                  { "question" => "How do I submit a record?", "answer" => "A person reads desk@example.com. Attach a private link, not a file. We reply within two weeks if it is a yes." },
                  { "question" => "Can I visit Night Shift?", "answer" => "The Lagos floor is a working studio. Write first. Do not arrive with a guest list." }
                ]
              }
            }
          ]
        }
      ].freeze
    end
  end
end
