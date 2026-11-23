# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Pharmacy
      module MedicationReview
        DEFINITION = {
          key: "medication_review",
          name: "Medication Review",
          description: "Annual medication therapy review with current medications, allergies, and health goals",
          category: "pharmacy",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Patient Information" }],
            [{ type: :input, width: "half", label: "Patient Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Primary Care Physician" }, { type: :input, width: "half", label: "Physician Phone" }],
            [{ type: :select, width: "half", label: "Review Type (Annual, Follow-up, New Patient)" }, { type: :date, width: "half", label: "Review Date" }],
            [{ type: :divider }],
            [{ type: :section, label: "Current Medications" }],
            [{ type: :textarea, width: "full", label: "Prescription Medications (name, dose, frequency, prescriber)" }],
            [{ type: :textarea, width: "full", label: "OTC Medications & Supplements (name, dose, how often)" }],
            [{ type: :radio, width: "full", label: "Are you taking all medications as prescribed?" }],
            [{ type: :select, width: "half", label: "Doses Missed per Week (None, 1-2, 3-4, Daily)" }, { type: :select, width: "half", label: "Reason for Missing (if any)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Health Information" }],
            [{ type: :textarea, width: "full", label: "Known Drug / Food Allergies & Reactions" }],
            [{ type: :checkbox, width: "full", label: "Health Conditions (Diabetes, Hypertension, Heart Disease, Asthma, COPD, Thyroid, Depression, Anxiety, Other)" }],
            [{ type: :radio, width: "full", label: "Any difficulty swallowing tablets or capsules?" }],
            [{ type: :radio, width: "full", label: "Experiencing any side effects from current medications?" }],
            [{ type: :textarea, width: "full", label: "Describe Side Effects or Concerns (if any)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Health Goals & Follow-up" }],
            [{ type: :textarea, width: "full", label: "Current Health Goals" }],
            [{ type: :select, width: "half", label: "Preferred Follow-up Method (Phone, In-Person, Email)" }, { type: :date, width: "half", label: "Preferred Follow-up Date" }],
            [{ type: :checkbox, width: "full", label: "I consent to pharmacist review and sharing of medication information with my care team" }]
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
              { label: "Medications", match_types: %w[textarea radio select] },
              { label: "Health & Goals", match_types: %w[checkbox] }
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
