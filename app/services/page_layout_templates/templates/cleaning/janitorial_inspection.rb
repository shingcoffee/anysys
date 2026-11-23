# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Cleaning
      module JanitorialInspection
        DEFINITION = {
          key: "janitorial_inspection",
          name: "Janitorial Inspection",
          description: "Cleaning quality inspection checklist with area ratings and corrective actions",
          category: "cleaning",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Inspection Details" }],
            [{ type: :input, width: "half", label: "Inspector Name" }, { type: :date, width: "half", label: "Inspection Date" }],
            [{ type: :input, width: "half", label: "Building / Facility" }, { type: :select, width: "half", label: "Floor / Zone" }],
            [{ type: :input, width: "half", label: "Cleaning Crew / Vendor" }, { type: :select, width: "half", label: "Shift (Day, Evening, Night)" }],
            [{ type: :select, width: "half", label: "Inspection Type (Routine, Random, Complaint Follow-Up)" }, { type: :input, width: "half", label: "Work Order / Reference #" }],
            [{ type: :divider }],
            [{ type: :section, label: "Area Ratings" }],
            [{ type: :select, width: "half", label: "Restrooms (1-Poor to 5-Excellent)" }, { type: :select, width: "half", label: "Common Areas (1-5)" }],
            [{ type: :select, width: "half", label: "Offices / Workspaces (1-5)" }, { type: :select, width: "half", label: "Kitchen / Break Room (1-5)" }],
            [{ type: :select, width: "half", label: "Entrances / Lobbies (1-5)" }, { type: :select, width: "half", label: "Hallways / Stairwells (1-5)" }],
            [{ type: :select, width: "half", label: "Conference Rooms (1-5)" }, { type: :select, width: "half", label: "Elevators (1-5)" }],
            [{ type: :select, width: "half", label: "Overall Cleanliness Score (1-5)" }, { type: :radio, width: "half", label: "Pass / Fail Overall?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Issues & Actions" }],
            [{ type: :checkbox, width: "full", label: "Issues Found (Missed Areas, Supply Shortage, Equipment Damage, Safety Hazard, Odor Issues, Staining, Graffiti, Pest Sighting)" }],
            [{ type: :textarea, width: "full", label: "Detailed Description of Issues" }],
            [{ type: :textarea, width: "full", label: "Corrective Actions Required" }],
            [{ type: :select, width: "half", label: "Priority Level (Low, Medium, High, Critical)" }, { type: :date, width: "half", label: "Follow-Up Date" }],
            [{ type: :file, width: "full", label: "Inspection Photos" }],
            [{ type: :signature, width: "full", label: "Inspector Signature" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
            },
            sections: [
              { label: "Inspection Info", match_types: %w[text date select] },
              { label: "Area Ratings", match_types: %w[radio] },
              { label: "Issues & Actions", match_types: %w[checkbox textarea file] }
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
