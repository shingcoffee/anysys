# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Pestcontrol
      module TreatmentFollowup
        DEFINITION = {
          key: "pest_treatment_followup",
          name: "Pest Treatment Follow-up",
          description: "Post-treatment follow-up report with effectiveness assessment, re-treatment needs, and customer satisfaction",
          category: "pestcontrol",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Customer Information" }],
            [{ type: :input, width: "half", label: "Customer Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Account Number" }],
            [{ type: :input, width: "full", label: "Service Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Treatment Assessment" }],
            [{ type: :date, width: "half", label: "Original Treatment Date" }, { type: :select, width: "half", label: "Pest Type Treated" }],
            [{ type: :select, width: "half", label: "Treatment Effectiveness (1-5)" }, { type: :select, width: "half", label: "Current Pest Activity Level (None, Low, Moderate, High)" }],
            [{ type: :radio, width: "full", label: "Have you observed pest activity since the treatment?" }],
            [{ type: :checkbox, width: "full", label: "Where are you seeing activity? (Kitchen, Bedroom, Basement, Exterior, Garden, Multiple)" }],
            [{ type: :select, width: "half", label: "How does current activity compare to before treatment?" }, { type: :select, width: "half", label: "Overall Satisfaction (1-5)" }],
            [{ type: :textarea, width: "full", label: "Describe Current Pest Activity or Concerns" }],
            [{ type: :file, width: "full", label: "Photos of Current Activity (optional)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Follow-up & Re-treatment" }],
            [{ type: :radio, width: "full", label: "Would you like to schedule a re-treatment or follow-up visit?" }],
            [{ type: :date, width: "half", label: "Preferred Re-treatment Date" }, { type: :select, width: "half", label: "Preferred Time Window" }],
            [{ type: :textarea, width: "full", label: "Additional Comments or Feedback" }]
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
              "file" => "full"
            },
            sections: [
              { label: "Customer Info", match_types: %w[text email tel] },
              { label: "Treatment Assessment", match_types: %w[date select radio checkbox] },
              { label: "Details & Follow-up", match_types: %w[textarea file] }
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
