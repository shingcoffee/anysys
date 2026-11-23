# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Roofing
      module RepairQuote
        DEFINITION = {
          key: "roof_repair_quote",
          name: "Roof Repair Quote",
          description: "Roofing repair or replacement quote with damage details, roof type, and urgency level",
          category: "roofing",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Homeowner Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "full", label: "Property Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Roof & Service Details" }],
            [{ type: :select, width: "half", label: "Current Roof Material (Asphalt, Metal, Tile, Flat, Wood Shake, Slate, Other)" }, { type: :select, width: "half", label: "Approximate Roof Age (< 5 yrs, 5-10 yrs, 10-20 yrs, 20+ yrs, Unknown)" }],
            [{ type: :select, width: "half", label: "Property Type (Single Family, Multi-Family, Commercial, Other)" }, { type: :number, width: "half", label: "Approximate Roof Sq Ft" }],
            [{ type: :select, width: "half", label: "Service Needed (Repair, Partial Replacement, Full Replacement, Inspection + Quote)" }, { type: :select, width: "half", label: "Urgency (Emergency, Within 1 Week, Within 1 Month, Planning Ahead)" }],
            [{ type: :radio, width: "full", label: "Is this related to an insurance claim?" }],
            [{ type: :input, width: "half", label: "Insurance Company (if applicable)" }, { type: :input, width: "half", label: "Claim / Policy Number (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Damage Description & Photos" }],
            [{ type: :checkbox, width: "full", label: "Issues Observed (Missing Shingles, Leaks, Sagging, Flashing Damage, Gutters, Skylights, Mold, Hail Damage, Wind Damage)" }],
            [{ type: :textarea, width: "full", label: "Describe the Damage or Work Needed" }],
            [{ type: :file, width: "full", label: "Upload Photos of Damage (optional)" }],
            [{ type: :date, width: "half", label: "Preferred Estimate Date" }, { type: :select, width: "half", label: "Best Time to Visit" }],
            [{ type: :checkbox, width: "full", label: "I authorize access to the property for inspection and quote" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "date" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact & Property", match_types: %w[text email tel] },
              { label: "Roof & Service Details", match_types: %w[select number radio] },
              { label: "Damage Description & Photos", match_types: %w[date checkbox textarea file] }
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
