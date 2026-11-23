# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Physicaltherapy
      module ProgressEvaluation
        DEFINITION = {
          key: "pt_progress_evaluation",
          name: "PT Progress Evaluation",
          description: "Physical therapy progress evaluation with functional improvements, pain tracking, and updated treatment goals",
          category: "physicaltherapy",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Session Information" }],
            [{ type: :input, width: "half", label: "Patient Name" }, { type: :input, width: "half", label: "Therapist Name" }],
            [{ type: :date, width: "half", label: "Evaluation Date" }, { type: :number, width: "half", label: "Session Number" }],
            [{ type: :select, width: "half", label: "Primary Treatment Area" }, { type: :select, width: "half", label: "Treatment Diagnosis" }],
            [{ type: :divider }],
            [{ type: :section, label: "Progress Assessment" }],
            [{ type: :select, width: "half", label: "Current Pain Level (1-10)" }, { type: :select, width: "half", label: "Pain Level at Start of Care (1-10)" }],
            [{ type: :select, width: "half", label: "Range of Motion (Full, Moderate, Limited, Severely Limited)" }, { type: :select, width: "half", label: "Strength Level (5/5, 4/5, 3/5, 2/5, 1/5)" }],
            [{ type: :select, width: "half", label: "Functional Improvement (Significant, Moderate, Minimal, None)" }, { type: :select, width: "half", label: "Overall Progress (Exceeding, On Track, Below Expectations)" }],
            [{ type: :checkbox, width: "full", label: "Milestones Achieved (Reduced Pain, Improved ROM, Increased Strength, Walking Independently, Return to Work, Return to Sport)" }],
            [{ type: :radio, width: "full", label: "Is the patient following the home exercise program?" }],
            [{ type: :radio, width: "full", label: "Any adverse reactions or complications since last session?" }],
            [{ type: :textarea, width: "full", label: "Clinical Observations and Progress Notes" }],
            [{ type: :divider }],
            [{ type: :section, label: "Treatment Plan & Next Steps" }],
            [{ type: :textarea, width: "full", label: "Updated Treatment Plan and Goals" }],
            [{ type: :radio, width: "full", label: "Recommend continued therapy?" }],
            [{ type: :select, width: "half", label: "Recommended Frequency (1x/wk, 2x/wk, 3x/wk, PRN)" }, { type: :number, width: "half", label: "Additional Sessions Requested" }],
            [{ type: :select, width: "half", label: "Discharge Timeline (1-2 wks, 1 month, 2-3 months, Ongoing)" }, { type: :date, width: "half", label: "Next Evaluation Date" }],
            [{ type: :checkbox, width: "full", label: "Patient has been informed of progress and updated goals" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "number" => "half",
              "select" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Patient & Session Info", match_types: %w[text email tel date number] },
              { label: "Progress Assessment", match_types: %w[select checkbox radio] },
              { label: "Notes & Treatment Plan", match_types: %w[textarea file] }
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
