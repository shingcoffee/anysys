# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Seniorcare
      module CareAssessment
        DEFINITION = {
          key: "senior_care_assessment",
          name: "Senior Care Assessment",
          description: "Comprehensive elder care needs assessment with medical history, mobility, daily living, and family contact",
          category: "seniorcare",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Resident Information" }],
            [{ type: :input, width: "half", label: "Resident Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :select, width: "half", label: "Gender" }],
            [{ type: :input, width: "full", label: "Current Home Address" }],
            [{ type: :select, width: "half", label: "Marital Status (Single, Married, Widowed, Divorced)" }, { type: :select, width: "half", label: "Primary Language" }],
            [{ type: :divider }],
            [{ type: :section, label: "Primary Contact / Family Member" }],
            [{ type: :input, width: "half", label: "Contact Full Name" }, { type: :input, width: "half", label: "Relationship to Resident" }],
            [{ type: :input, width: "half", label: "Contact Phone" }, { type: :input, width: "half", label: "Contact Email" }],
            [{ type: :radio, width: "full", label: "Is this contact the legal guardian or power of attorney?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Health & Daily Living" }],
            [{ type: :textarea, width: "full", label: "Current Medical Conditions / Diagnoses" }],
            [{ type: :textarea, width: "full", label: "Current Medications (name, dose, frequency)" }],
            [{ type: :input, width: "half", label: "Primary Care Physician" }, { type: :input, width: "half", label: "Physician Phone" }],
            [{ type: :select, width: "half", label: "Mobility Level (Independent, Assisted, Wheelchair, Bedridden)" }, { type: :select, width: "half", label: "Cognitive Status (Intact, Mild Decline, Moderate, Severe)" }],
            [{ type: :checkbox, width: "full", label: "Assistance Needed With (Bathing, Dressing, Grooming, Meals, Medication, Mobility, Housekeeping, Transportation, Memory Support)" }],
            [{ type: :radio, width: "full", label: "Does the resident have any known allergies (food or medication)?" }],
            [{ type: :textarea, width: "full", label: "Describe Allergies (if yes)" }],
            [{ type: :select, width: "half", label: "Care Level Requested (Companion, Personal Care, Skilled Nursing, Memory Care, Respite)" }, { type: :date, width: "half", label: "Preferred Care Start Date" }],
            [{ type: :textarea, width: "full", label: "Additional Notes, Preferences, or Special Requests" }],
            [{ type: :checkbox, width: "full", label: "I authorize the release of medical information for care planning purposes" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "textarea" => "full",
              "checkbox" => "full",
              "radio" => "full"
            },
            sections: [
              { label: "Resident & Family", match_types: %w[text email tel date] },
              { label: "Health & Conditions", match_types: %w[textarea radio] },
              { label: "Care Needs", match_types: %w[select checkbox] }
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
