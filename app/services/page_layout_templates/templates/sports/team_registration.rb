# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Sports
      module TeamRegistration
        DEFINITION = {
          key: "team_registration",
          name: "Team Registration",
          description: "Sports league or team signup with player info, position, and waiver",
          category: "sports",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Player Information" }],
            [{ type: :input, width: "half", label: "Player Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :input, width: "half", label: "Parent / Guardian Name (if minor)" }, { type: :input, width: "half", label: "Guardian Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Team & Sport Details" }],
            [{ type: :select, width: "half", label: "Sport" }, { type: :select, width: "half", label: "Division / Age Group" }],
            [{ type: :input, width: "half", label: "Team Name" }, { type: :input, width: "half", label: "Coach Name" }],
            [{ type: :select, width: "half", label: "Primary Position" }, { type: :select, width: "half", label: "Secondary Position" }],
            [{ type: :select, width: "half", label: "Jersey Size" }, { type: :number, width: "half", label: "Preferred Jersey Number" }],
            [{ type: :radio, width: "full", label: "Experience Level (Beginner, Intermediate, Advanced, Elite)" }],
            [{ type: :number, width: "half", label: "Years Playing This Sport" }, { type: :select, width: "half", label: "Season (Spring, Fall, Winter, Year-round)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Health & Emergency" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :textarea, width: "full", label: "Medical Conditions, Allergies, or Physical Limitations" }],
            [{ type: :radio, width: "full", label: "Cleared by a doctor for physical activity?" }],
            [{ type: :checkbox, width: "full", label: "I accept the liability waiver and agree to league rules and code of conduct" }],
            [{ type: :signature, width: "full", label: "Player / Guardian Signature" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
            },
            sections: [
              { label: "Player Info", match_types: %w[text email tel date] },
              { label: "Team & Sport", match_types: %w[select number radio] },
              { label: "Health & Waiver", match_types: %w[textarea checkbox] }
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
