# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Energy
      module SolarQuote
        DEFINITION = {
          key: "solar_quote",
          name: "Solar Installation Quote",
          description: "Residential or commercial solar panel quote with roof details, energy usage, and financing preferences",
          category: "energy",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Best Time to Call" }],
            [{ type: :input, width: "full", label: "Property Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Property & Energy Details" }],
            [{ type: :select, width: "half", label: "Property Type (Residential, Commercial, Agricultural, Industrial)" }, { type: :radio, width: "half", label: "Do you own or rent?" }],
            [{ type: :select, width: "half", label: "Roof Type (Asphalt Shingle, Tile, Metal, Flat, Other)" }, { type: :select, width: "half", label: "Roof Age (< 5 yrs, 5-10 yrs, 10-20 yrs, 20+ yrs)" }],
            [{ type: :select, width: "half", label: "Roof Condition" }, { type: :select, width: "half", label: "Roof Orientation (South, East/West, North, Flat)" }],
            [{ type: :number, width: "half", label: "Average Monthly Electric Bill ($)" }, { type: :input, width: "half", label: "Current Utility Provider" }],
            [{ type: :number, width: "half", label: "Property Square Footage" }, { type: :select, width: "half", label: "Number of Floors" }],
            [{ type: :divider }],
            [{ type: :section, label: "Goals & Financing" }],
            [{ type: :checkbox, width: "full", label: "Primary Goals (Reduce Bill, Energy Independence, Environment, EV Charging, Backup Power)" }],
            [{ type: :select, width: "half", label: "Preferred Financing Option (Cash Purchase, Loan, Lease, PPA)" }, { type: :radio, width: "half", label: "Interested in Battery Storage?" }],
            [{ type: :radio, width: "full", label: "Have you received solar quotes before?" }],
            [{ type: :textarea, width: "full", label: "Additional Questions or Special Requirements" }],
            [{ type: :file, width: "full", label: "Recent Utility Bill or Roof Photo (optional)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Property & Energy", match_types: %w[select number radio checkbox] },
              { label: "Notes & Photos", match_types: %w[textarea file] }
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
