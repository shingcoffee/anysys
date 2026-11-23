# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Sports
      module PlayerRegistration
        DEFINITION = {
          key: "player_registration",
          name: "Player Registration",
          description: "Individual athlete registration with personal details, medical clearance, and waiver",
          category: "sports",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :select, width: "half", label: "Gender" }, { type: :select, width: "half", label: "Age Group / Division" }],
            [{ type: :divider }],
            [{ type: :section, label: "Sport Details" }],
            [{ type: :select, width: "half", label: "Sport" }, { type: :select, width: "half", label: "Primary Position / Role" }],
            [{ type: :select, width: "half", label: "Secondary Position (optional)" }, { type: :select, width: "half", label: "Skill Level (Beginner, Intermediate, Advanced, Elite)" }],
            [{ type: :select, width: "half", label: "Preferred Team (if applicable)" }, { type: :number, width: "half", label: "Years of Experience" }],
            [{ type: :select, width: "half", label: "Jersey Size (XS, S, M, L, XL, XXL)" }, { type: :input, width: "half", label: "Jersey Number Preference" }],
            [{ type: :select, width: "half", label: "Season / League" }, { type: :date, width: "half", label: "Registration Date" }],
            [{ type: :divider }],
            [{ type: :section, label: "Medical & Waiver" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :textarea, width: "full", label: "Medical Conditions, Injuries, or Allergies" }],
            [{ type: :radio, width: "full", label: "Has player received physician clearance to participate?" }],
            [{ type: :file, width: "full", label: "Upload Medical Clearance Form (if required)" }],
            [{ type: :signature, width: "full", label: "Player / Guardian Signature — Liability Waiver" }],
            [{ type: :checkbox, width: "full", label: "I accept the liability waiver and consent to participation in all related activities" }]
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
              "textarea" => "full",
              "checkbox" => "full",
              "radio" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Personal Info", match_types: %w[text email tel date] },
              { label: "Sport Details", match_types: %w[select number] },
              { label: "Medical & Waiver", match_types: %w[textarea radio file checkbox] }
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
