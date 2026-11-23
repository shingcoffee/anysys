# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Energy
      module OutageReport
        DEFINITION = {
          key: "outage_report",
          name: "Outage Report",
          description: "Utility service outage report with location, type of outage, and safety hazard details",
          category: "energy",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Contact & Account" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Account Number" }],
            [{ type: :input, width: "full", label: "Service Address (where outage is occurring)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Outage Details" }],
            [{ type: :select, width: "half", label: "Outage Type (Power, Gas, Water, Internet, Other)" }, { type: :select, width: "half", label: "Area Affected (Single Home, Block, Neighborhood, Larger Area)" }],
            [{ type: :date, width: "half", label: "Date Outage Noticed" }, { type: :select, width: "half", label: "Approximate Time Noticed" }],
            [{ type: :select, width: "half", label: "Duration of Outage (Just started, < 1 hr, 1-4 hrs, 4+ hrs)" }, { type: :select, width: "half", label: "Number of Affected Units / Meters" }],
            [{ type: :radio, width: "full", label: "Is there a visible safety hazard (downed wires, gas smell, sparks)?" }],
            [{ type: :checkbox, width: "full", label: "Hazard Types (Downed Power Line, Gas Leak, Sparks/Fire, Flooding, Damaged Equipment, Other)" }],
            [{ type: :radio, width: "full", label: "Have emergency services been contacted?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Description & Evidence" }],
            [{ type: :textarea, width: "full", label: "Description of the outage or damage" }],
            [{ type: :file, width: "full", label: "Photos of hazard, damage, or affected area" }],
            [{ type: :checkbox, width: "full", label: "I confirm this information is accurate and I am the account holder or authorized representative" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Contact & Account", match_types: %w[text email tel] },
              { label: "Outage Details", match_types: %w[select date radio checkbox time] },
              { label: "Description & Evidence", match_types: %w[textarea file] }
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
