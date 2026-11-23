# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Physicaltherapy
      module PtIntake
        DEFINITION = {
          key: "pt_intake",
          name: "Physical Therapy Intake",
          description: "New patient intake for physical therapy with injury details, pain assessment, mobility goals, and medical history",
          category: "physicaltherapy",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Patient Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :input, width: "half", label: "Insurance Provider" }, { type: :input, width: "half", label: "Policy / Member Number" }],
            [{ type: :input, width: "half", label: "Referring Physician" }, { type: :input, width: "half", label: "Physician Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Condition & Pain Assessment" }],
            [{ type: :select, width: "half", label: "Primary Area of Concern (Neck, Shoulder, Back, Hip, Knee, Ankle, Other)" }, { type: :select, width: "half", label: "Condition Type (Injury, Post-Surgery, Chronic Pain, Sports, Other)" }],
            [{ type: :date, width: "half", label: "When Did Symptoms Begin?" }, { type: :select, width: "half", label: "Current Pain Level (1-10)" }],
            [{ type: :select, width: "half", label: "Pain Frequency (Constant, Intermittent, With Activity)" }, { type: :select, width: "half", label: "What Makes Pain Worse?" }],
            [{ type: :checkbox, width: "full", label: "Pain Characteristics (Sharp, Dull, Burning, Aching, Numbness, Tingling, Stiffness)" }],
            [{ type: :textarea, width: "full", label: "Describe Symptoms and How They Affect Daily Activities" }],
            [{ type: :divider }],
            [{ type: :section, label: "Medical History & Goals" }],
            [{ type: :radio, width: "full", label: "Previous physical therapy for this condition?" }],
            [{ type: :radio, width: "full", label: "Recent surgery related to this condition?" }],
            [{ type: :radio, width: "full", label: "Currently using any assistive devices (brace, cane, walker)?" }],
            [{ type: :checkbox, width: "full", label: "Other Medical Conditions (Diabetes, Heart Disease, Osteoporosis, Arthritis, Hypertension, Cancer, Other)" }],
            [{ type: :textarea, width: "full", label: "Current Medications and Dosages" }],
            [{ type: :textarea, width: "full", label: "Therapy Goals — What Would You Like to Achieve?" }],
            [{ type: :file, width: "full", label: "Upload Referral, Imaging, or Prior Records (optional)" }],
            [{ type: :checkbox, width: "full", label: "I authorize release of medical information and consent to physical therapy evaluation and treatment" }]
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
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Patient Information", match_types: %w[text email tel date] },
              { label: "Condition & Pain Assessment", match_types: %w[select checkbox] },
              { label: "Medical History & Goals", match_types: %w[radio textarea file] }
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
