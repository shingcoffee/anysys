# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Dental
      module CosmeticConsultation
        DEFINITION = {
          key: "cosmetic_consultation",
          name: "Cosmetic Dental Consultation",
          description: "Cosmetic dentistry consultation with smile goals, treatment interest, and dental history",
          category: "dental",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Patient Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :input, width: "half", label: "Referring Doctor / Source (if any)" }, { type: :select, width: "half", label: "How did you hear about us?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Treatment Goals" }],
            [{ type: :checkbox, width: "full", label: "Treatments of Interest (Teeth Whitening, Veneers, Bonding, Invisalign, Implants, Gum Contouring, Smile Makeover)" }],
            [{ type: :textarea, width: "full", label: "Describe your smile goals" }],
            [{ type: :select, width: "half", label: "Desired Outcome (Whiter, Straighter, Fuller, Natural Look, Other)" }, { type: :select, width: "half", label: "Timeline for Treatment" }],
            [{ type: :select, width: "half", label: "Budget Range" }, { type: :select, width: "half", label: "Financing Interest (Cash, Insurance, Financing Plan)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Dental History" }],
            [{ type: :radio, width: "full", label: "Have you had cosmetic dental work before?" }],
            [{ type: :textarea, width: "full", label: "Current dental concerns or sensitivities" }],
            [{ type: :radio, width: "full", label: "Do you grind or clench your teeth?" }],
            [{ type: :radio, width: "full", label: "Do you have any known allergies to dental materials?" }],
            [{ type: :select, width: "half", label: "Preferred Appointment Day" }, { type: :select, width: "half", label: "Preferred Time" }],
            [{ type: :file, width: "full", label: "Current Smile Photo (optional)" }],
            [{ type: :checkbox, width: "full", label: "I consent to photos being used for treatment planning purposes" }]
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
              "file" => "full"
            },
            sections: [
              { label: "Personal Info", match_types: %w[text email tel date] },
              { label: "Treatment Goals", match_types: %w[checkbox select radio textarea] },
              { label: "Scheduling & Photos", match_types: %w[file] }
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
