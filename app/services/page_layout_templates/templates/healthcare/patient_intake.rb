# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Healthcare
      module PatientIntake
        DEFINITION = {
          key: "patient_intake",
          name: "Patient Intake",
          description: "Medical intake with demographics, insurance, and consent",
          category: "healthcare",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Patient Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :select, width: "half", label: "Gender" }, { type: :select, width: "half", label: "Marital Status" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Insurance" }],
            [{ type: :input, width: "half", label: "Insurance Provider" }, { type: :input, width: "half", label: "Policy Number" }],
            [{ type: :input, width: "half", label: "Group Number" }, { type: :input, width: "half", label: "Insured's Name (if different)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Medical History" }],
            [{ type: :textarea, width: "full", label: "Current Medications & Dosages" }],
            [{ type: :textarea, width: "full", label: "Known Allergies (Medications, Food, Environmental)" }],
            [{ type: :checkbox, width: "full", label: "Past Medical History: Diabetes, Hypertension, Heart Disease, Cancer, Stroke, Asthma, Mental Health, Surgery" }],
            [{ type: :radio, width: "full", label: "Do you smoke or use tobacco?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Consent" }],
            [{ type: :checkbox, width: "full", label: "I consent to examination, testing, and treatment" }],
            [{ type: :checkbox, width: "full", label: "I have received and acknowledge the Notice of Privacy Practices (HIPAA)" }],
            [{ type: :signature, width: "full", label: "Patient Signature" }]
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
            },
            sections: [
              { label: "Patient Info", match_types: %w[text email tel date select] },
              { label: "Medical History", match_types: %w[textarea checkbox radio] },
              { label: "Consent & Signature", match_types: %w[] }
            ],
            inject_elements: [
              { after_section: 0, type: "divider" },
              { after_section: 1, type: "divider" },
              { after_section: 2, type: "divider" }
            ]
          }
        }.freeze
      end
    end
  end
end
