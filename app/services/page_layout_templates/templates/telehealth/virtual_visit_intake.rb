# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Telehealth
      module VirtualVisitIntake
        DEFINITION = {
          key: "virtual_visit_intake",
          name: "Virtual Visit Intake",
          description: "Telehealth pre-visit questionnaire with symptoms, medical history, and technology readiness",
          category: "telehealth",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Patient Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Home Address (for prescriptions and records)" }],
            [{ type: :select, width: "half", label: "Gender" }, { type: :select, width: "half", label: "Preferred Language" }],
            [{ type: :input, width: "half", label: "Insurance Provider" }, { type: :input, width: "half", label: "Member ID / Group Number" }],
            [{ type: :divider }],
            [{ type: :section, label: "Symptoms & History" }],
            [{ type: :select, width: "half", label: "Reason for Visit" }, { type: :select, width: "half", label: "Preferred Provider (if any)" }],
            [{ type: :checkbox, width: "full", label: "Current Symptoms (Fever, Cough, Sore Throat, Fatigue, Nausea, Headache, Rash, Shortness of Breath, Pain, Other)" }],
            [{ type: :select, width: "half", label: "Symptom Duration (Today, 2-3 Days, 1 Week, 2+ Weeks)" }, { type: :select, width: "half", label: "Symptom Severity (Mild, Moderate, Severe)" }],
            [{ type: :textarea, width: "full", label: "Describe Your Symptoms in Detail" }],
            [{ type: :textarea, width: "full", label: "Current Medications (name, dose, frequency)" }],
            [{ type: :textarea, width: "full", label: "Known Allergies (medications, food, environmental)" }],
            [{ type: :checkbox, width: "full", label: "Chronic Conditions (Diabetes, Hypertension, Heart Disease, Asthma, COPD, Thyroid, Depression, Other)" }],
            [{ type: :radio, width: "full", label: "Have you been seen for this issue before (in-person or virtual)?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Tech & Consent" }],
            [{ type: :select, width: "half", label: "Preferred Device (Computer, Tablet, Smartphone)" }, { type: :radio, width: "half", label: "Camera and microphone working?" }],
            [{ type: :date, width: "half", label: "Preferred Appointment Date" }, { type: :select, width: "half", label: "Preferred Time" }],
            [{ type: :checkbox, width: "full", label: "I consent to telehealth services and electronic transmission of my health information" }]
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
              { label: "Patient Info", match_types: %w[text email tel date] },
              { label: "Symptoms & History", match_types: %w[select checkbox textarea radio] },
              { label: "Tech & Consent", match_types: %w[] }
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
