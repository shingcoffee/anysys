# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Creative
      module PhotographyBooking
        DEFINITION = {
          key: "photography_booking",
          name: "Photography Booking",
          description: "Photography session request with event type, date, and style preferences",
          category: "creative",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Client Details" }],
            [{ type: :input, width: "half", label: "Client Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Instagram / Social Handle (optional)" }],
            [{ type: :input, width: "half", label: "City / Location" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Session Details" }],
            [{ type: :select, width: "half", label: "Session Type (Portrait, Wedding, Event, Commercial, Newborn, Family, Maternity, Boudoir, Other)" }, { type: :select, width: "half", label: "Package" }],
            [{ type: :date, width: "half", label: "Preferred Date" }, { type: :select, width: "half", label: "Preferred Time" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Session Duration (1 hr, 2 hrs, Half Day, Full Day)" }],
            [{ type: :input, width: "full", label: "Shooting Location / Venue Address" }],
            [{ type: :number, width: "half", label: "Number of People / Subjects" }, { type: :select, width: "half", label: "Budget Range" }],
            [{ type: :radio, width: "full", label: "Is this an indoor or outdoor session?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Style & Requests" }],
            [{ type: :checkbox, width: "full", label: "Style Preferences (Natural Light, Moody, Bright & Airy, Dark & Dramatic, Film, Editorial, Candid)" }],
            [{ type: :textarea, width: "full", label: "Vision, Theme, or Special Requests" }],
            [{ type: :radio, width: "full", label: "Do you need prints, digital files, or both?" }],
            [{ type: :radio, width: "full", label: "Do you need hair and makeup referrals?" }],
            [{ type: :file, width: "full", label: "Upload Inspiration Photos (optional)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Client Details", match_types: %w[text email tel] },
              { label: "Session Details", match_types: %w[select date number radio time] },
              { label: "Style & Requests", match_types: %w[checkbox textarea file] }
            ],
            inject_elements: [
              { after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }
            ]
          }
        }.freeze
      end
    end
  end
end
