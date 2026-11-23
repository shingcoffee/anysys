# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Tattoo
      module AftercareCheckin
        DEFINITION = {
          key: "tattoo_aftercare_checkin",
          name: "Tattoo Aftercare Check-in",
          description: "Post-tattoo healing check-in form with healing progress, concerns, and follow-up photo upload",
          category: "tattoo",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Client & Session Info" }],
            [{ type: :input, width: "half", label: "Client Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Artist Name" }],
            [{ type: :date, width: "half", label: "Date of Tattoo Session" }, { type: :select, width: "half", label: "Body Placement" }],
            [{ type: :divider }],
            [{ type: :section, label: "Healing Progress" }],
            [{ type: :select, width: "half", label: "Days Since Session (1-3, 4-7, 1-2 Weeks, 2-4 Weeks, 1+ Month)" }, { type: :select, width: "half", label: "Overall Healing (Excellent, Good, Fair, Concerning)" }],
            [{ type: :checkbox, width: "full", label: "Current Symptoms (Normal Peeling, Redness, Swelling, Itching, Scabbing, Fading, Ink Loss, Raised Areas, Discharge)" }],
            [{ type: :radio, width: "full", label: "Are you following the aftercare instructions provided?" }],
            [{ type: :select, width: "half", label: "Aftercare Product Used" }, { type: :radio, width: "half", label: "Any signs of infection (heat, pus, fever)?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Concerns & Photos" }],
            [{ type: :textarea, width: "full", label: "Describe Any Concerns or Questions" }],
            [{ type: :file, width: "full", label: "Upload Healing Progress Photos (optional)" }],
            [{ type: :radio, width: "full", label: "Would you like to schedule a touch-up session?" }],
            [{ type: :date, width: "half", label: "Preferred Touch-up Date (if yes)" }, { type: :select, width: "half", label: "Preferred Time Window" }],
            [{ type: :select, width: "half", label: "Overall Satisfaction with Tattoo (1-5)" }, { type: :radio, width: "half", label: "Would you return for future work?" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Client & Session Info", match_types: %w[text email tel date] },
              { label: "Healing Progress", match_types: %w[select checkbox radio] },
              { label: "Concerns & Photos", match_types: %w[textarea file] }
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
