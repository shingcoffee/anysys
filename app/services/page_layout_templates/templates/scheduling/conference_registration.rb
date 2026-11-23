# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Scheduling
      module ConferenceRegistration
        DEFINITION = {
          key: "conference_registration",
          name: "Conference Registration",
          description: "Multi-session conference signup with workshops and meal selection",
          category: "scheduling",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Attendee Information" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Company / Organization" }, { type: :input, width: "half", label: "Job Title" }],
            [{ type: :input, width: "half", label: "Industry" }, { type: :select, width: "half", label: "Country" }],
            [{ type: :divider }],
            [{ type: :section, label: "Registration & Sessions" }],
            [{ type: :select, width: "half", label: "Registration Type (In-Person, Virtual, Hybrid)" }, { type: :select, width: "half", label: "Ticket Tier (Standard, VIP, Student)" }],
            [{ type: :select, width: "half", label: "Preferred Track / Focus Area" }, { type: :select, width: "half", label: "Day 1 Keynote Session" }],
            [{ type: :checkbox, width: "full", label: "Pre-Conference Workshops (Workshop A, Workshop B, Workshop C, Workshop D)" }],
            [{ type: :select, width: "half", label: "Day 2 Breakout Session" }, { type: :select, width: "half", label: "Day 3 Breakout Session" }],
            [{ type: :divider }],
            [{ type: :section, label: "Preferences & Logistics" }],
            [{ type: :select, width: "half", label: "Meal Preference" }, { type: :select, width: "half", label: "T-Shirt Size" }],
            [{ type: :checkbox, width: "full", label: "Dietary Restrictions (Vegetarian, Vegan, Gluten-Free, Nut Allergy, Halal, Kosher)" }],
            [{ type: :radio, width: "full", label: "Need hotel accommodation assistance?" }],
            [{ type: :radio, width: "full", label: "Require accessibility accommodations?" }],
            [{ type: :input, width: "half", label: "Promo / Discount Code" }, { type: :select, width: "half", label: "Payment Method" }],
            [{ type: :textarea, width: "full", label: "Special Requests or Notes" }],
            [{ type: :checkbox, width: "full", label: "I agree to the event code of conduct and cancellation policy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Attendee Information", match_types: %w[text email tel url] },
              { label: "Session & Workshop Selection", match_types: %w[select checkbox radio] },
              { label: "Preferences & Notes", match_types: %w[textarea] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
