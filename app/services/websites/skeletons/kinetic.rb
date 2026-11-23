# frozen_string_literal: true

module Websites
  module Skeletons
    module Kinetic
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "kinetic_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "High performance living",
                "headline" => "It's not fitness. It's life.",
                "subhead" => "Training, recovery and coaching under one roof, for people who take the whole of their health seriously.",
                "primary_label" => "Book a tour",
                "primary_href" => "membership",
                "secondary_label" => "View classes",
                "secondary_href" => "classes",
                "tone" => "dark"
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "300+", "label" => "classes a week" },
                  { "value" => "12", "label" => "clubs" },
                  { "value" => "85", "label" => "master trainers" },
                  { "value" => "24/7", "label" => "app coaching" }
                ]
              }
            },
            {
              "type" => "bento_grid",
              "props" => {
                "kicker" => "The club",
                "heading" => "Everything you need to perform",
                "cells" => [
                  { "span" => "hero", "title" => "Strength floor", "body" => "Platforms, racks and space to move without waiting." },
                  { "span" => "unit", "title" => "Recovery suite", "body" => "Cold plunge, sauna and compression." },
                  { "span" => "unit", "title" => "Studios", "body" => "Cycle, yoga, boxing and pilates." },
                  { "span" => "wide", "title" => "Personal training", "body" => "A coach, a plan and measurable progress every month." }
                ]
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "heading" => "Members on the floor",
                "items" => [
                  { "quote" => "My trainer rebuilt my running from the ground up. I just finished my first marathon.", "name" => "Alex T.", "role" => "Member, Downtown" },
                  { "quote" => "The recovery suite alone is worth it. I sleep better than I have in years.", "name" => "Nadia S.", "role" => "Member, Riverside" },
                  { "quote" => "Classes are hard in the best possible way. Nobody coasts here.", "name" => "Chris M.", "role" => "Member, Midtown" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Your first week is on us",
                "body" => "Tour a club, take any class and meet a trainer before you commit.",
                "button_label" => "Claim your pass",
                "button_href" => "membership"
              }
            }
          ]
        },
        {
          "title" => "Classes",
          "slug" => "classes",
          "home" => false,
          "nav_visible" => true,
          "role" => "classes",
          "layout_key" => "kinetic_classes",
          "sections" => [
            {
              "type" => "hero_centered",
              "props" => {
                "eyebrow" => "Classes",
                "headline" => "Find the class that finds your limit",
                "subhead" => "Over three hundred sessions a week, led by instructors who train like athletes.",
                "primary_label" => "Book a class",
                "primary_href" => "membership"
              }
            },
            {
              "type" => "card_grid",
              "props" => {
                "heading" => "Disciplines",
                "cards" => [
                  { "title" => "Strength", "body" => "Barbell, kettlebell and bodyweight programmes.", "href" => "membership" },
                  { "title" => "Cycle", "body" => "Rhythm rides and power-based intervals.", "href" => "membership" },
                  { "title" => "Mind and body", "body" => "Yoga, breathwork and mobility.", "href" => "membership" }
                ]
              }
            },
            {
              "type" => "agenda",
              "props" => {
                "kicker" => "Timetable",
                "heading" => "Today at Hudson Yards",
                "subhead" => "Book up to seven days ahead in the app. Classes are 45 minutes unless noted.",
                "sessions" => [
                  { "time" => "06:00", "title" => "Precision Run", "speaker" => "Coach Maya", "body" => "Treadmill intervals built on pace, not guesswork.", "track" => "Studio 1" },
                  { "time" => "07:15", "title" => "Barbell Strength", "speaker" => "Coach Dev", "track" => "Performance floor" },
                  { "time" => "12:00", "title" => "Rhythm Ride", "speaker" => "Coach Lena", "track" => "Cycle studio" },
                  { "time" => "18:30", "title" => "Vinyasa Flow", "speaker" => "Coach Aiko", "body" => "60 minutes. Mats and blocks provided.", "track" => "Mind and body" },
                  { "time" => "20:00", "title" => "Recovery and breathwork", "speaker" => "Coach Sam", "track" => "Spa level" }
                ]
              }
            },
            {
              "type" => "steps",
              "props" => {
                "heading" => "Your first month",
                "items" => [
                  { "title" => "Assessment", "body" => "Movement screen and body composition with a coach." },
                  { "title" => "Programme", "body" => "A plan built around your goals and your calendar." },
                  { "title" => "Progress", "body" => "Monthly check-ins to measure, adjust and push further." }
                ]
              }
            }
          ]
        },
        {
          "title" => "Membership",
          "slug" => "membership",
          "home" => false,
          "nav_visible" => true,
          "role" => "membership",
          "layout_key" => "kinetic_membership",
          "sections" => [
            {
              "type" => "pricing",
              "props" => {
                "kicker" => "Membership",
                "heading" => "Choose how you train",
                "tiers" => [
                  {
                    "name" => "Club",
                    "price" => "$220",
                    "cadence" => "per month",
                    "body" => "Unlimited access to your home club.",
                    "features" => "All classes\nRecovery suite\nApp coaching",
                    "button_label" => "Join",
                    "button_href" => "contact",
                    "highlight" => "standard"
                  },
                  {
                    "name" => "All Access",
                    "price" => "$290",
                    "cadence" => "per month",
                    "body" => "Every club, everywhere.",
                    "features" => "Everything in Club\nAll twelve locations\nGuest passes each month",
                    "button_label" => "Join All Access",
                    "button_href" => "contact",
                    "highlight" => "featured"
                  },
                  {
                    "name" => "Coached",
                    "price" => "$650",
                    "cadence" => "per month",
                    "body" => "All Access plus a dedicated trainer.",
                    "features" => "Everything in All Access\nWeekly personal training\nNutrition coaching",
                    "button_label" => "Talk to a coach",
                    "button_href" => "contact",
                    "highlight" => "standard"
                  }
                ]
              }
            },
            {
              "type" => "faq",
              "props" => {
                "heading" => "Membership questions",
                "items" => [
                  { "question" => "Is there a joining fee?", "answer" => "Not when you join online during your free first week." },
                  { "question" => "Can I freeze my membership?", "answer" => "Yes, for up to three months a year for travel or injury." }
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
          "layout_key" => "kinetic_contact",
          "sections" => [
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Clubs",
                "heading" => "Train at any club",
                "subhead" => "Every membership includes a guest pass for your first visit to each location.",
                "places" => [
                  { "name" => "Hudson Yards", "address" => "120 Hudson Street\nNew York, NY", "hours" => "Weekdays 5:00–23:00\nWeekends 7:00–21:00", "phone" => "+1 212 555 0170", "button_label" => "Book a tour", "button_href" => "membership" },
                  { "name" => "Sunset Strip", "address" => "8590 Sunset Boulevard\nWest Hollywood, CA", "hours" => "Weekdays 5:00–22:00\nWeekends 7:00–20:00", "phone" => "+1 310 555 0144", "button_label" => "Book a tour", "button_href" => "membership" },
                  { "name" => "Kensington", "address" => "99 Kensington High Street\nLondon W8", "hours" => "Weekdays 6:00–22:00\nWeekends 8:00–20:00", "phone" => "+44 20 5555 0177", "button_label" => "Book a tour", "button_href" => "membership" }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Talk to the membership team",
                "address" => "120 Hudson Street, Floor 9\nNew York, NY",
                "email" => "members@example.com",
                "phone" => "+1 212 555 0100",
                "hours" => "Monday–Friday, 8:00–20:00"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
