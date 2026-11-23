# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Construction
      module BuildingInspection
        DEFINITION = {
          key: "building_inspection",
          name: "Building Inspection",
          description: "Property inspection checklist with photos, defects, and compliance notes",
          category: "construction",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Property & Inspector" }],
            [{ type: :input, width: "full", label: "Property Address" }],
            [{ type: :input, width: "half", label: "Inspector Name" }, { type: :input, width: "half", label: "License #" }],
            [{ type: :date, width: "half", label: "Inspection Date" }, { type: :select, width: "half", label: "Inspection Type (Pre-Purchase, Annual, Code Compliance, Post-Repair)" }],
            [{ type: :select, width: "half", label: "Property Type (Residential, Commercial, Industrial, Multi-Unit)" }, { type: :number, width: "half", label: "Year Built" }],
            [{ type: :number, width: "half", label: "Square Footage" }, { type: :select, width: "half", label: "Number of Stories" }],
            [{ type: :input, width: "half", label: "Client / Owner Name" }, { type: :input, width: "half", label: "Client Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Inspection Checklist" }],
            [{ type: :select, width: "half", label: "Foundation (Pass, Fail, Needs Repair, N/A)" }, { type: :select, width: "half", label: "Roof / Gutters (Pass, Fail, Needs Repair, N/A)" }],
            [{ type: :select, width: "half", label: "Electrical (Pass, Fail, Needs Repair, N/A)" }, { type: :select, width: "half", label: "Plumbing (Pass, Fail, Needs Repair, N/A)" }],
            [{ type: :select, width: "half", label: "HVAC (Pass, Fail, Needs Repair, N/A)" }, { type: :select, width: "half", label: "Structure / Framing (Pass, Fail, Needs Repair, N/A)" }],
            [{ type: :select, width: "half", label: "Windows / Doors (Pass, Fail, Needs Repair, N/A)" }, { type: :select, width: "half", label: "Insulation / Ventilation (Pass, Fail, Needs Repair, N/A)" }],
            [{ type: :select, width: "half", label: "Interior Walls / Ceilings (Pass, Fail, Needs Repair, N/A)" }, { type: :select, width: "half", label: "Exterior Cladding (Pass, Fail, Needs Repair, N/A)" }],
            [{ type: :radio, width: "full", label: "Are there visible signs of water intrusion or mold?" }],
            [{ type: :radio, width: "full", label: "Are smoke and CO detectors installed and functioning?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Findings & Recommendations" }],
            [{ type: :checkbox, width: "full", label: "Major Issues (Safety Hazard, Code Violation, Structural Damage, Water Damage, Electrical Risk, Mold, Pest Damage)" }],
            [{ type: :textarea, width: "full", label: "Defects Found & Details" }],
            [{ type: :textarea, width: "full", label: "Recommendations & Repair Priorities" }],
            [{ type: :select, width: "half", label: "Overall Condition (Excellent, Good, Fair, Poor)" }, { type: :select, width: "half", label: "Urgency of Repairs (Immediate, Within 30 Days, Within 90 Days, Monitor)" }],
            [{ type: :file, width: "full", label: "Upload Inspection Photos" }],
            [{ type: :signature, width: "full", label: "Inspector Signature" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
            },
            sections: [
              { label: "Property Info", match_types: %w[text email date select number] },
              { label: "Inspection Checklist", match_types: %w[radio] },
              { label: "Findings & Photos", match_types: %w[textarea checkbox file] }
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
