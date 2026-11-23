# frozen_string_literal: true

module Websites
  module Skeletons
    # Headspace register: a warm mindfulness product — sessions you will
    # actually finish, sleep stories, and a voice that never scolds.
    module Calm
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "calm_home",
          "sections" => [
            {
              "type" => "announcement",
              "props" => {
                "badge" => "This week",
                "body" => "A new ten-minute evening sit with Mara — rain on the roof, nothing to fix.",
                "link_label" => "Play it tonight",
                "href" => "practice",
                "surface" => "accent"
              }
            },
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "A kinder day",
                "headline" => "Take ten minutes. The rest of the day gets quieter.",
                "subhead" => "Short sits, sleep stories and a walk you can do between meetings. No streaks to break. No one keeping score.",
                "primary_label" => "Try a session",
                "primary_href" => "practice",
                "secondary_label" => "How membership works",
                "secondary_href" => "about",
                "tone" => "light"
              }
            },
            {
              "type" => "metrics",
              "props" => {
                "kicker" => "Among members",
                "heading" => "Small numbers, kept honestly",
                "items" => [
                  { "value" => "10 min", "label" => "most common session", "body" => "Long enough to notice, short enough to finish before the kettle." },
                  { "value" => "4.2×", "label" => "nights with a sleep story", "body" => "Members who play one at bedtime report falling asleep faster in week two." },
                  { "value" => "68", "label" => "languages and voices", "body" => "A sit in the voice you grew up with, or the one you prefer at night." },
                  { "value" => "0", "label" => "guilt if you miss a day", "body" => "We will not send a badge. The session will still be here tomorrow." }
                ],
                "align" => "center",
                "surface" => "muted"
              }
            },
            {
              "type" => "collection_rail",
              "props" => {
                "kicker" => "Start here",
                "heading" => "Sessions people actually finish",
                "subhead" => "Pick a length. We will not upsell you a longer one.",
                "aspect" => "landscape",
                "items" => [
                  { "title" => "Three breaths", "meta" => "2 min · Mara", "href" => "practice" },
                  { "title" => "A walk around the block", "meta" => "8 min · outdoor", "href" => "practice" },
                  { "title" => "Rain on the roof", "meta" => "10 min · evening", "href" => "practice" },
                  { "title" => "The Sunday sit", "meta" => "15 min · Jules", "href" => "practice" },
                  { "title" => "Falling through snow", "meta" => "Sleep story · 22 min", "href" => "practice" },
                  { "title" => "Kitchen light", "meta" => "Sleep radio · all night", "href" => "practice" }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "kicker" => "Members",
                "heading" => "What people say after a month",
                "items" => [
                  { "quote" => "I do the two-minute one between school drop-off and the inbox. That is the whole practice, and it is enough.", "name" => "Hannah Cole", "role" => "Member since March" },
                  { "quote" => "The sleep stories are the first thing that got my son to stay in bed without a negotiation.", "name" => "Omar Farid", "role" => "Family plan" },
                  { "quote" => "Nobody clapped when I finished a sit. That is why I stayed.", "name" => "Lina Berg", "role" => "Year two" }
                ],
                "surface" => "muted",
                "align" => "center"
              }
            },
            {
              "type" => "cta_split",
              "props" => {
                "kicker" => "Seven days, on us",
                "headline" => "Listen to one session before you pay",
                "body" => "The library opens for a week. Cancel from the same screen you started on. We will not hide the button.",
                "primary_label" => "Start the week",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "Read member stories",
                "secondary_href" => "stories",
                "image_side" => "left"
              }
            }
          ]
        },
        {
          "title" => "Practice",
          "slug" => "practice",
          "home" => false,
          "nav_visible" => true,
          "role" => "practice",
          "layout_key" => "calm_practice",
          "sections" => [
            {
              "type" => "split_checklist",
              "props" => {
                "kicker" => "How it feels",
                "heading" => "A practice that fits a real Tuesday",
                "body" => "No incense required. Headphones help. A closed door is a luxury, not a rule.",
                "button_label" => "Play the two-minute sit",
                "button_href" => "https://example.com/start",
                "items" => [
                  { "title" => "Pick a length, not a level", "body" => "Two, ten or twenty. We will not call you a beginner." },
                  { "title" => "A voice you can live with", "body" => "Mara, Jules, or a sit with almost no talking at all." },
                  { "title" => "Download for the train", "body" => "Offline packs for the commute and the flight." },
                  { "title" => "A kids' corner that is not syrupy", "body" => "Short sits and sleep stories written with actual children in the room." },
                  { "title" => "Reminders you can mute", "body" => "One nudge at the time you chose. Or none." }
                ]
              }
            },
            {
              "type" => "feature_tabs",
              "props" => {
                "kicker" => "The library",
                "heading" => "Sits, walks, sleep, and the odd course",
                "subhead" => "New sessions land on Thursdays. Older ones stay. We do not bury last year's work.",
                "tabs" => [
                  { "label" => "Sits", "title" => "From two minutes to a Sunday", "body" => "Breath, body, a little guidance. Stop whenever you like — the session will not scold you." },
                  { "label" => "Walks", "title" => "For the block you already walk", "body" => "Look up, name three sounds, come back. Designed for pavements, not trails." },
                  { "label" => "Sleep", "title" => "Stories and radio for the last half hour", "body" => "A plot that does not ask you to stay awake. Rain, snow, a kitchen at 1am." },
                  { "label" => "Courses", "title" => "Ten days, one idea", "body" => "Anxiety, focus, a kinder inner voice. Miss a day and the next one still unlocks." }
                ],
                "align" => "start",
                "spacing" => "roomy"
              }
            },
            {
              "type" => "collection_rail",
              "props" => {
                "kicker" => "Tonight",
                "heading" => "If you only open the app once",
                "aspect" => "square",
                "items" => [
                  { "title" => "Rain on the roof", "meta" => "10 min", "href" => "practice" },
                  { "title" => "Falling through snow", "meta" => "22 min sleep", "href" => "practice" },
                  { "title" => "Three breaths", "meta" => "2 min", "href" => "practice" },
                  { "title" => "The long exhale", "meta" => "6 min", "href" => "practice" },
                  { "title" => "Kitchen light", "meta" => "Sleep radio", "href" => "practice" },
                  { "title" => "A walk at dusk", "meta" => "12 min", "href" => "practice" }
                ],
                "surface" => "muted"
              }
            },
            {
              "type" => "steps",
              "props" => {
                "kicker" => "Your first week",
                "heading" => "We will not give you homework",
                "items" => [
                  { "title" => "Day one", "body" => "Play the two-minute sit. That is the whole assignment." },
                  { "title" => "Day three", "body" => "Try a walk, or the same sit again. Repetition is not failure." },
                  { "title" => "Day seven", "body" => "If a sleep story helped, keep it. If nothing landed, write to us — we will refund the week." }
                ],
                "align" => "start"
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "Practical things",
                "items" => [
                  { "question" => "Do I need to sit on the floor?", "answer" => "No. A chair, a commute, the edge of a bed. Comfort is the point." },
                  { "question" => "Can I share an account?", "answer" => "The family plan covers six people. Kids get their own library." },
                  { "question" => "What if I hate the voice?", "answer" => "Switch it. Every session has at least two readers, and a version with almost no talking." }
                ]
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
          "layout_key" => "calm_stories",
          "sections" => [
            {
              "type" => "story_index",
              "props" => {
                "kicker" => "Field notes",
                "heading" => "How people actually use it",
                "stories" => [
                  { "kicker" => "Member", "title" => "Ten minutes in the car, before I go inside", "body" => "Hannah on the sit that lives between school and the inbox.", "byline" => "4 min", "href" => "stories" },
                  { "kicker" => "Sleep", "title" => "The story my son now asks for by name", "byline" => "5 min", "href" => "stories" },
                  { "kicker" => "Work", "title" => "We put a sit on the calendar and called it a meeting", "byline" => "6 min", "href" => "stories" },
                  { "kicker" => "Voice", "title" => "Why Mara records in a room with the window open", "byline" => "Profile", "href" => "about" },
                  { "kicker" => "Course", "title" => "Anxiety, ten days, no homework", "byline" => "7 min", "href" => "practice" },
                  { "kicker" => "Family", "title" => "Six logins, one kitchen, surprisingly little fighting", "byline" => "5 min", "href" => "stories" }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "I do not feel improved. I feel slightly more like a person. That was the brief.",
                "attribution" => "Lina Berg",
                "role" => "Member, year two",
                "surface" => "muted"
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "heading" => "Short notes from the library",
                "items" => [
                  { "quote" => "The walk sessions made the same block feel like a place again.", "name" => "Chris Adeyemi", "role" => "Member" },
                  { "quote" => "I cancelled two other apps. This one never made me feel behind.", "name" => "Sofia Ren", "role" => "Member" },
                  { "quote" => "We play kitchen light on the speaker and nobody talks about it. Perfect.", "name" => "The Okonks", "role" => "Family plan" }
                ],
                "align" => "center"
              }
            },
            {
              "type" => "split_image_text",
              "props" => {
                "heading" => "We record in rooms that already have a life",
                "body" => "A kitchen after dinner. A porch in light rain. The point is not a studio — it is a voice you would trust in the next room.",
                "image_side" => "right"
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
          "layout_key" => "calm_about",
          "sections" => [
            {
              "type" => "statement",
              "props" => {
                "kicker" => "About Calm",
                "headline" => "We make the ten minutes that make the rest of the day possible.",
                "body" => "Not a lifestyle. Not a leaderboard. A sit you can finish, a story that lets a house go quiet, and a reminder you are allowed to mute."
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "kicker" => "Voices and makers",
                "heading" => "The people in your headphones",
                "people" => [
                  { "name" => "Mara Ellison", "role" => "Teacher", "bio" => "Records with the window open. Believes two minutes counts." },
                  { "name" => "Jules Okonkwo", "role" => "Teacher", "bio" => "Writes the walks. Used to be a city bus driver." },
                  { "name" => "Noor Rahman", "role" => "Sleep stories", "bio" => "Plots that wander on purpose and never ask you to stay." },
                  { "name" => "Eli Park", "role" => "Product", "bio" => "Deletes more features than they ship." }
                ],
                "surface" => "muted"
              }
            },
            {
              "type" => "timeline",
              "props" => {
                "kicker" => "How we got here",
                "heading" => "A short history of taking it slowly",
                "items" => [
                  { "date" => "2016", "title" => "A single sit on a phone", "body" => "Mara, a kitchen table, and a refusal to add points." },
                  { "date" => "2019", "title" => "Sleep stories", "body" => "The first one was about snow. People wrote to say they missed the ending. Good." },
                  { "date" => "2022", "title" => "Family plan", "body" => "Kids got their own library. Adults kept theirs." },
                  { "date" => "2025", "title" => "Still no streaks", "body" => "We get asked every year. The answer is still no." }
                ]
              }
            },
            {
              "type" => "cta_split",
              "props" => {
                "kicker" => "Membership",
                "headline" => "One price. The whole library. Cancel any day.",
                "body" => "$69 a year, or $12.99 a month. Students and teachers pay half. The family plan is $99 for six people.",
                "primary_label" => "Start seven days free",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "Write to us",
                "secondary_href" => "contact",
                "image_side" => "right"
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
          "layout_key" => "calm_contact",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "A person will write back",
                "address" => "18 Garden Walk\nBrighton",
                "email" => "hello@example.com",
                "phone" => "+44 1273 555 010",
                "hours" => "Monday–Friday, 9:00–17:00 UK"
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "Before you write",
                "items" => [
                  { "question" => "Can I gift a year?", "answer" => "Yes. We will send a note in your words, or none at all." },
                  { "question" => "Do you have a studio I can visit?", "answer" => "We record in rooms, not a showroom. Write if you are press or a partner — we will find a table." }
                ],
                "surface" => "muted"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
