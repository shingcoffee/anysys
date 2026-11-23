# frozen_string_literal: true

module Websites
  module Skeletons
    module Clinic
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "clinic_home",
          "sections" => [
            {
              "type" => "hero_split",
              "props" => {
                "eyebrow" => "Now accepting new members",
                "headline" => "Primary care that works around your life",
                "subhead" => "Same-day appointments, 24/7 video visits and a care team that actually knows you.",
                "primary_label" => "Become a member",
                "primary_href" => "membership",
                "secondary_label" => "How it works",
                "secondary_href" => "care"
              }
            },
            {
              "type" => "logo_cloud",
              "props" => {
                "heading" => "In network with most major insurance plans",
                "items" => [
                  { "name" => "Aetna" },
                  { "name" => "Cigna" },
                  { "name" => "UnitedHealthcare" },
                  { "name" => "Blue Shield" },
                  { "name" => "Humana" }
                ]
              }
            },
            {
              "type" => "steps",
              "props" => {
                "kicker" => "How it works",
                "heading" => "Care in three simple steps",
                "items" => [
                  { "title" => "Join in minutes", "body" => "Sign up online and choose a clinician who fits you." },
                  { "title" => "Book when it suits you", "body" => "Same or next-day visits in person, or video chat anytime." },
                  { "title" => "Stay connected", "body" => "Message your care team, view results and renew prescriptions in the app." }
                ]
              }
            },
            {
              "type" => "feature_grid",
              "props" => {
                "kicker" => "What's included",
                "heading" => "Everything you expect from a doctor, and more",
                "items" => [
                  { "title" => "Preventive care", "body" => "Annual physicals, screenings and vaccines on your schedule." },
                  { "title" => "Everyday illness", "body" => "Colds, infections and injuries handled quickly, often the same day." },
                  { "title" => "Chronic conditions", "body" => "Ongoing support for diabetes, asthma and heart health." },
                  { "title" => "Mental health", "body" => "Therapy and psychiatry integrated with your primary care." },
                  { "title" => "Lab work on site", "body" => "Blood draws in the office, results in the app." },
                  { "title" => "Care for the whole family", "body" => "Pediatrics and adult care under one membership." }
                ]
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "heading" => "What members say",
                "items" => [
                  { "quote" => "I booked at 8 a.m. and was seen by 10. My doctor had already read my history.", "name" => "Rachel K.", "role" => "Member since 2021" },
                  { "quote" => "The app is the first health tool I actually open. Messages get answered within the hour.", "name" => "Marcus L.", "role" => "Member since 2022" },
                  { "quote" => "Finally a practice that treats my anxiety and my asthma like parts of the same person.", "name" => "Jenna P.", "role" => "Member since 2020" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Better care starts with a better relationship",
                "body" => "Join today and book your first visit this week.",
                "button_label" => "Get started",
                "button_href" => "membership"
              }
            }
          ]
        },
        {
          "title" => "Care",
          "slug" => "care",
          "home" => false,
          "nav_visible" => true,
          "role" => "care",
          "layout_key" => "clinic_care",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Our care",
                "headline" => "Designed around people, not waiting rooms",
                "tone" => "light",
                "subhead" => "Calm offices, longer visits and clinicians who have time to listen."
              }
            },
            {
              "type" => "alternating_features",
              "props" => {
                "heading" => "A different kind of practice",
                "items" => [
                  { "title" => "Longer appointments", "body" => "Visits are scheduled with room to talk, so nothing important gets rushed." },
                  { "title" => "Offices that feel human", "body" => "Daylight, quiet and no clipboards. Check in from your phone." },
                  { "title" => "Care between visits", "body" => "Your team follows up, reminds and adjusts — not just when you are in the room." }
                ]
              }
            },
            {
              "type" => "team_grid",
              "props" => {
                "kicker" => "Clinicians",
                "heading" => "Meet the care team",
                "people" => [
                  { "name" => "Dr. Amara Okafor", "role" => "Family medicine", "bio" => "Focuses on preventive care and women's health." },
                  { "name" => "Dr. James Whitfield", "role" => "Internal medicine", "bio" => "Special interest in heart health and sleep." },
                  { "name" => "Dr. Lucia Fernández", "role" => "Pediatrics", "bio" => "Has seen three generations of the same families." },
                  { "name" => "Dr. Kenji Watanabe", "role" => "Psychiatry", "bio" => "Believes mental health is primary care." }
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
          "layout_key" => "clinic_membership",
          "sections" => [
            {
              "type" => "pricing",
              "props" => {
                "kicker" => "Membership",
                "heading" => "One simple membership",
                "subhead" => "Most insurance accepted for visits. Membership covers everything else.",
                "tiers" => [
                  {
                    "name" => "Individual",
                    "price" => "$199",
                    "cadence" => "per year",
                    "body" => "Everything you need for your own care.",
                    "features" => "Same or next-day visits\n24/7 video chat\nApp messaging\nOn-site labs",
                    "button_label" => "Join now",
                    "button_href" => "contact",
                    "highlight" => "featured"
                  },
                  {
                    "name" => "Family",
                    "price" => "$349",
                    "cadence" => "per year",
                    "body" => "For two adults and children under 18.",
                    "features" => "Everything in Individual\nPediatric care\nShared family account",
                    "button_label" => "Join as a family",
                    "button_href" => "contact",
                    "highlight" => "standard"
                  }
                ]
              }
            },
            {
              "type" => "faq",
              "props" => {
                "kicker" => "FAQ",
                "heading" => "Questions about membership",
                "items" => [
                  { "question" => "Do I still need insurance?", "answer" => "We recommend it. Visits are billed to insurance; membership covers the service around them." },
                  { "question" => "Can I cancel?", "answer" => "Yes. Cancel anytime and receive a prorated refund for unused months." },
                  { "question" => "Is there a waitlist?", "answer" => "Not in most cities. You can usually book your first visit within a week." }
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
          "layout_key" => "clinic_contact",
          "sections" => [
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Visit an office",
                "address" => "1 Market Street, Suite 200\nSan Francisco, CA",
                "email" => "care@example.com",
                "phone" => "+1 888 555 0199",
                "hours" => "Monday–Friday, 7:00–19:00\nSaturday, 9:00–17:00"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
