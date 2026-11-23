# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Healthcare
      module HealthAssessment
        DEFINITION = {
          key: "health_assessment",
          name: "Health Assessment",
          description: "Wellness questionnaire with symptom checklist and scales",
          category: "healthcare",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Patient Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Assessment Date" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :select, width: "half", label: "Gender" }],
            [{ type: :number, width: "half", label: "Height (cm)" }, { type: :number, width: "half", label: "Weight (kg)" }],
            [{ type: :input, width: "half", label: "Primary Care Physician" }, { type: :input, width: "half", label: "Patient ID / MRN (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Symptoms & Conditions" }],
            [{ type: :checkbox, width: "full", label: "Current Symptoms (Headache, Fatigue, Dizziness, Fever, Cough, Shortness of Breath, Chest Pain, Nausea, Joint Pain, Insomnia, Other)" }],
            [{ type: :select, width: "half", label: "Pain Level (0-None to 10-Severe)" }, { type: :select, width: "half", label: "Duration of Symptoms (Days, Weeks, Months, Ongoing)" }],
            [{ type: :radio, width: "full", label: "Have you seen a doctor about these symptoms recently?" }],
            [{ type: :checkbox, width: "full", label: "Existing Medical Conditions (Diabetes, Hypertension, Heart Disease, Asthma, Cancer, Thyroid, Autoimmune, Mental Health, Kidney Disease)" }],
            [{ type: :radio, width: "full", label: "Do you have any known drug allergies?" }],
            [{ type: :textarea, width: "full", label: "Drug Allergies and Reactions (if any)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Lifestyle & Notes" }],
            [{ type: :select, width: "half", label: "Smoking Status (Never, Former, Current)" }, { type: :select, width: "half", label: "Alcohol Use (None, Occasional, Moderate, Heavy)" }],
            [{ type: :select, width: "half", label: "Physical Activity Level (Sedentary, Light, Moderate, Active)" }, { type: :select, width: "half", label: "Diet Quality (Poor, Fair, Good, Excellent)" }],
            [{ type: :textarea, width: "full", label: "Current Medications or Supplements" }],
            [{ type: :textarea, width: "full", label: "Additional Notes or Health Concerns" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "date" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "range" => "full",
            },
            sections: [
              { label: "Patient Info", match_types: %w[text email tel date number] },
              { label: "Symptoms & Conditions", match_types: %w[checkbox radio select] },
              { label: "Lifestyle & Notes", match_types: %w[textarea] }
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
