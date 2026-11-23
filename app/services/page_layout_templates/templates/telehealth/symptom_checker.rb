# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Telehealth
      module SymptomChecker
        DEFINITION = {
          key: "symptom_checker",
          name: "Symptom Checker",
          description: "Pre-screening symptom assessment to help triage patients before a telehealth consultation",
          category: "telehealth",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Patient Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :select, width: "half", label: "Gender" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :select, width: "half", label: "Age Group (Child, Adolescent, Adult, Senior)" }, { type: :select, width: "half", label: "Current Location (Home, Work, Travel, Other)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Symptoms" }],
            [{ type: :select, width: "half", label: "Primary Symptom" }, { type: :select, width: "half", label: "Affected Body Area" }],
            [{ type: :select, width: "half", label: "Symptom Onset (Today, 2-3 Days, 1 Week, 2+ Weeks)" }, { type: :select, width: "half", label: "Severity (1-10)" }],
            [{ type: :checkbox, width: "full", label: "Associated Symptoms (Fever, Chills, Fatigue, Nausea, Vomiting, Shortness of Breath, Chest Pain, Rash, Dizziness, Swelling)" }],
            [{ type: :radio, width: "full", label: "Are your symptoms getting worse?" }],
            [{ type: :radio, width: "full", label: "Do you have a fever above 101°F / 38.3°C?" }],
            [{ type: :select, width: "half", label: "Temperature (°F) if measured" }, { type: :select, width: "half", label: "Oxygen Level (%) if measured" }],
            [{ type: :divider }],
            [{ type: :section, label: "Details" }],
            [{ type: :radio, width: "full", label: "Have you seen a doctor for this before?" }],
            [{ type: :radio, width: "full", label: "Currently taking any medication for this condition?" }],
            [{ type: :radio, width: "full", label: "Any underlying chronic conditions (diabetes, heart disease, asthma, etc.)?" }],
            [{ type: :textarea, width: "full", label: "Additional Details or Context" }],
            [{ type: :checkbox, width: "full", label: "I understand this is a screening tool and not a medical diagnosis" }]
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
              "range" => "full",
            },
            sections: [
              { label: "Patient Info", match_types: %w[text email tel date] },
              { label: "Symptoms", match_types: %w[select checkbox radio range] },
              { label: "Details", match_types: %w[textarea] }
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
