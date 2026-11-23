# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Pestcontrol
      module InspectionRequest
        DEFINITION = {
          key: "pest_inspection_request",
          name: "Pest Inspection Request",
          description: "Pest control inspection request with pest type, property details, and infestation severity",
          category: "pestcontrol",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "full", label: "Property Address" }],
            [{ type: :select, width: "half", label: "Property Type (Residential, Commercial, Industrial, Agricultural)" }, { type: :radio, width: "half", label: "Own or Rent?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Pest & Infestation Details" }],
            [{ type: :checkbox, width: "full", label: "Pest Type(s) Observed (Ants, Cockroaches, Termites, Mice/Rats, Bedbugs, Mosquitoes, Spiders, Wasps, Other)" }],
            [{ type: :select, width: "half", label: "Infestation Severity (Minor, Moderate, Severe, Unsure)" }, { type: :select, width: "half", label: "First Noticed (This Week, This Month, 1-3 Months Ago, Longer)" }],
            [{ type: :checkbox, width: "full", label: "Areas Affected (Kitchen, Bedroom, Bathroom, Basement, Attic, Garage, Garden, Multiple Areas)" }],
            [{ type: :radio, width: "full", label: "Children or pets in the home?" }],
            [{ type: :radio, width: "full", label: "Previous pest treatments in the last 12 months?" }],
            [{ type: :textarea, width: "full", label: "Describe the Infestation or Concern" }],
            [{ type: :file, width: "full", label: "Photos of Pests or Damage (optional)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Scheduling" }],
            [{ type: :date, width: "half", label: "Preferred Inspection Date" }, { type: :select, width: "half", label: "Preferred Time Window" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time Window" }],
            [{ type: :checkbox, width: "full", label: "I authorize entry to the property for inspection" }]
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
              "file" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Contact & Property", match_types: %w[text email tel] },
              { label: "Pest Details", match_types: %w[select checkbox radio] },
              { label: "Schedule & Photos", match_types: %w[date textarea file time] }
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
