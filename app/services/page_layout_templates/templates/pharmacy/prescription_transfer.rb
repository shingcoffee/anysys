# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Pharmacy
      module PrescriptionTransfer
        DEFINITION = {
          key: "prescription_transfer",
          name: "Prescription Transfer",
          description: "Transfer prescriptions from another pharmacy with medication and insurance details",
          category: "pharmacy",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Patient Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :input, width: "half", label: "Allergies (if known)" }, { type: :select, width: "half", label: "Preferred Contact Method" }],
            [{ type: :divider }],
            [{ type: :section, label: "Current Pharmacy" }],
            [{ type: :input, width: "half", label: "Pharmacy Name" }, { type: :input, width: "half", label: "Pharmacy Phone Number" }],
            [{ type: :input, width: "full", label: "Pharmacy Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Medication Details" }],
            [{ type: :input, width: "half", label: "Medication Name" }, { type: :input, width: "half", label: "Rx Number" }],
            [{ type: :input, width: "half", label: "Dosage / Strength" }, { type: :input, width: "half", label: "Prescribing Doctor" }],
            [{ type: :select, width: "half", label: "Refills Remaining (if known)" }, { type: :select, width: "half", label: "Preferred Pickup / Delivery" }],
            [{ type: :input, width: "half", label: "Second Medication Name (if any)" }, { type: :input, width: "half", label: "Second Rx Number" }],
            [{ type: :divider }],
            [{ type: :section, label: "Insurance & Authorization" }],
            [{ type: :radio, width: "full", label: "Do you have prescription insurance?" }],
            [{ type: :input, width: "half", label: "Insurance Provider" }, { type: :input, width: "half", label: "Member ID / Group Number" }],
            [{ type: :checkbox, width: "full", label: "I authorize the transfer of my prescriptions and release of medical information to this pharmacy" }]
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
              { label: "Patient Info", match_types: %w[text email tel date] },
              { label: "Pharmacy & Medication", match_types: %w[select radio] },
              { label: "Insurance & Authorization", match_types: %w[checkbox] }
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
