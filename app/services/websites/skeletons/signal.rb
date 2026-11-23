# frozen_string_literal: true

module Websites
  module Skeletons
    # Linear register: a dark product chapter, a bento, and a changelog.
    module Signal
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "signal_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Issue tracking, rebuilt",
                "headline" => "The tool your team actually opens",
                "subhead" => "Fast enough to stay in the flow. Quiet enough that the work stays the point.",
                "primary_label" => "Get started",
                "primary_href" => "https://example.com/start",
                "secondary_label" => "Read the log",
                "secondary_href" => "changelog",
                "tone" => "dark"
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "heading" => "Designed for speed",
                "cells" => [
                  { "span" => "hero", "title" => "Keyboard first", "body" => "Create, assign, and close without reaching for the mouse." },
                  { "span" => "wide", "title" => "Cycles, not sprints theater", "body" => "A two-week rhythm with a burndown that tells the truth." },
                  { "span" => "unit", "title" => "Projects", "body" => "A home for the bet, not a graveyard of tickets." },
                  { "span" => "unit", "title" => "Insights", "body" => "One chart. The one your lead already asks for." }
                ]
              }
            },
            {
              "type" => "alternating_features",
              "props" => {
                "heading" => "From idea to shipped",
                "items" => [
                  { "title" => "Capture without a template", "body" => "A new issue is a sentence. Fields appear when you need them." },
                  { "title" => "See the work, not the status meeting", "body" => "The board is the meeting. Decisions stay on the issue." }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "We deleted the other tracker. Nobody asked for it back.",
                "attribution" => "Jonah Park",
                "role" => "Head of Product"
              }
            },
            {
              "type" => "logo_cloud",
              "props" => {
                "heading" => "The tracker of choice for fast-moving teams",
                "items" => [{ "name" => "Parallel" }, { "name" => "Kite" }, { "name" => "Monolith" }, { "name" => "Arcadia" }, { "name" => "Vector" }]
              }
            },
            {
              "type" => "feature_grid",
              "props" => {
                "kicker" => "Under the hood",
                "heading" => "Fast is a feature",
                "items" => [
                  { "title" => "Local-first sync", "body" => "Every action lands instantly and syncs in the background." },
                  { "title" => "Command menu", "body" => "Everything is one keystroke away. The mouse is optional." },
                  { "title" => "Git integration", "body" => "Issues close themselves when the pull request merges." },
                  { "title" => "Triage inbox", "body" => "New requests land in one queue, not in five channels." },
                  { "title" => "Roadmaps", "body" => "Projects roll up into a plan leadership can actually read." },
                  { "title" => "API and webhooks", "body" => "Automate the busywork with a typed, documented API." }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Start a workspace tonight",
                "body" => "Import the backlog. Invite the team. Leave the rest.",
                "button_label" => "Create a workspace",
                "button_href" => "https://example.com/start"
              }
            }
          ]
        },
        {
          "title" => "Changelog",
          "slug" => "changelog",
          "home" => false,
          "nav_visible" => true,
          "role" => "changelog",
          "layout_key" => "signal_changelog",
          "sections" => [
            {
              "type" => "timeline",
              "props" => {
                "kicker" => "Changelog",
                "heading" => "What shipped",
                "subhead" => "Short notes, every week. The product speaks for itself.",
                "items" => [
                  { "date" => "Sep 24, 2026", "title" => "Cycles, redesigned", "body" => "A calmer way to plan the next two weeks: automatic rollover, a cooldown week and a burn-up that tells the truth." },
                  { "date" => "Sep 10, 2026", "title" => "Triage", "body" => "Inbox zero for issues, without a new ritual. Accept, decline or snooze with one key." },
                  { "date" => "Aug 27, 2026", "title" => "Slack threads to issues", "body" => "Create an issue from the thread that started it. Replies sync both ways." },
                  { "date" => "Aug 13, 2026", "title" => "Faster search", "body" => "Results in under 50 ms across every workspace, including closed issues." },
                  { "date" => "Jul 30, 2026", "title" => "Project updates", "body" => "A weekly health check that writes itself from the work you already did." }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "The changelog is the roadmap. We stopped writing the other one.",
                "attribution" => "Studio"
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
          "layout_key" => "signal_about",
          "sections" => [
            {
              "type" => "rich_text",
              "props" => {
                "heading" => "A small team, a sharp tool",
                "body" => "We build the software we wanted on Monday morning. Craft is the constraint. Speed is the courtesy."
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Come see it",
                "body" => "A twenty-minute walkthrough. Your backlog, not our slides.",
                "button_label" => "Book a time",
                "button_href" => "https://example.com/start"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
