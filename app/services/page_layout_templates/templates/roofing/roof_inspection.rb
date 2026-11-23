# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Roofing
      module RoofInspection
        DEFINITION = {
          key: "roof_inspection",
          name: "Roof Inspection Request",
          description: "Roof inspection or repair estimate with roof type, age, damage description, and insurance details",
          category: "roofing",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "full", label: "Property Address" }],
            [{ type: :radio, width: "full", label: "Do you own or rent this property?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Roof Details" }],
            [{ type: :select, width: "half", label: "Roof Material (Asphalt Shingles, Metal, Tile, Flat/TPO, Wood Shake, Slate, Other)" }, { type: :select, width: "half", label: "Approximate Roof Age (< 5 yrs, 5-10 yrs, 10-20 yrs, 20+ yrs, Unknown)" }],
            [{ type: :select, width: "half", label: "Number of Stories" }, { type: :select, width: "half", label: "Service Needed (Inspection, Repair, Full Replacement, Estimate Only)" }],
            [{ type: :checkbox, width: "full", label: "Visible Issues (Missing Shingles, Leaks, Sagging, Granule Loss, Damaged Flashing, Mold/Moss, Gutter Problems)" }],
            [{ type: :radio, width: "full", label: "Storm or weather-related damage?" }],
            [{ type: :radio, width: "full", label: "Planning to file an insurance claim?" }],
            [{ type: :input, width: "half", label: "Insurance Company (if applicable)" }, { type: :input, width: "half", label: "Claim Number (if applicable)" }],
            [{ type: :textarea, width: "full", label: "Describe the Issue in Detail" }],
            [{ type: :file, width: "full", label: "Upload Photos of Damage (optional)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Scheduling" }],
            [{ type: :date, width: "half", label: "Preferred Inspection Date" }, { type: :select, width: "half", label: "Preferred Time Window" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time Window" }],
            [{ type: :checkbox, width: "full", label: "I authorize access to the property for roof inspection" }]
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
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Contact & Property", match_types: %w[text email tel radio] },
              { label: "Roof & Issue", match_types: %w[select checkbox textarea file] },
              { label: "Schedule", match_types: %w[date] }
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
