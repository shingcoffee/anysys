# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Landscaping
      module LawnCareQuote
        DEFINITION = {
          key: "lawn_care_quote",
          name: "Lawn Care Quote",
          description: "Residential or commercial lawn service estimate with property size, services, and scheduling",
          category: "landscaping",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "full", label: "Property Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Property Details" }],
            [{ type: :select, width: "half", label: "Property Type (Residential, Commercial, HOA, Municipal)" }, { type: :select, width: "half", label: "Lot / Lawn Size" }],
            [{ type: :select, width: "half", label: "Grass Type (if known)" }, { type: :select, width: "half", label: "Irrigation System Present?" }],
            [{ type: :radio, width: "full", label: "Currently under a lawn care contract?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Services & Scheduling" }],
            [{ type: :checkbox, width: "full", label: "Services Requested (Mowing, Edging, Fertilizing, Weed Control, Aeration, Seeding, Mulching, Cleanup, Irrigation, Other)" }],
            [{ type: :select, width: "half", label: "Service Frequency (Weekly, Bi-Weekly, Monthly, One-Time)" }, { type: :select, width: "half", label: "Preferred Day of Week" }],
            [{ type: :date, width: "half", label: "Preferred Start Date" }, { type: :select, width: "half", label: "Preferred Time of Day" }],
            [{ type: :textarea, width: "full", label: "Describe Your Yard & Any Problem Areas" }],
            [{ type: :file, width: "full", label: "Property Photos (optional)" }],
            [{ type: :checkbox, width: "full", label: "I consent to being contacted with a quote" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Property & Services", match_types: %w[select date radio checkbox] },
              { label: "Details & Photos", match_types: %w[textarea file] }
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
