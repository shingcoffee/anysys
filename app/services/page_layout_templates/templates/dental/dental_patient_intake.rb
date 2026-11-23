# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Dental
      module DentalPatientIntake
        DEFINITION = {
          key: "dental_patient_intake",
          name: "Dental Patient Intake",
          description: "New dental patient form with medical history, insurance, and oral health",
          category: "dental",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Patient Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :select, width: "half", label: "Gender" }, { type: :select, width: "half", label: "Preferred Pronouns" }],
            [{ type: :select, width: "half", label: "Marital Status" }, { type: :input, width: "half", label: "Employer / Occupation" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :select, width: "half", label: "Emergency Contact Relationship" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Insurance" }],
            [{ type: :input, width: "half", label: "Primary Insurance Provider" }, { type: :input, width: "half", label: "Policy Number" }],
            [{ type: :input, width: "half", label: "Group Number" }, { type: :input, width: "half", label: "Insured's Name (if different from patient)" }],
            [{ type: :select, width: "half", label: "Relationship to Insured" }, { type: :radio, width: "half", label: "Do you have secondary dental insurance?" }],
            [{ type: :input, width: "half", label: "Secondary Insurance Provider" }, { type: :input, width: "half", label: "Secondary Policy Number" }],
            [{ type: :divider }],
            [{ type: :section, label: "Health Details" }],
            [{ type: :date, width: "half", label: "Date of Last Dental Visit" }, { type: :input, width: "half", label: "Previous Dentist Name" }],
            [{ type: :radio, width: "full", label: "Do you experience dental anxiety?" }],
            [{ type: :radio, width: "full", label: "Are you in pain or discomfort today?" }],
            [{ type: :checkbox, width: "full", label: "Current Dental Issues (Toothache, Sensitivity, Bleeding Gums, Bad Breath, Jaw Pain, Loose Teeth, Dry Mouth, Grinding/Clenching)" }],
            [{ type: :textarea, width: "full", label: "Medical Conditions (Diabetes, Heart Disease, Blood Disorder, Cancer, Stroke, Other)" }],
            [{ type: :textarea, width: "full", label: "Current Medications, Vitamins, or Supplements" }],
            [{ type: :textarea, width: "full", label: "Known Drug or Material Allergies" }],
            [{ type: :radio, width: "full", label: "Are you pregnant or nursing?" }],
            [{ type: :radio, width: "full", label: "Do you use tobacco products?" }],
            [{ type: :checkbox, width: "full", label: "I authorize the dental office to proceed with recommended treatment and release information to my insurance provider" }]
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
              "textarea" => "full"
            },
            sections: [
              { label: "Personal Info", match_types: %w[text email tel date select] },
              { label: "Insurance", match_types: %w[radio] },
              { label: "Health Details", match_types: %w[checkbox textarea] }
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
