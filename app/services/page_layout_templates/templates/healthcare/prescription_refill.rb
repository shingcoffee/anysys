# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Healthcare
      module PrescriptionRefill
        DEFINITION = {
          key: "prescription_refill",
          name: "Prescription Refill",
          description: "Pharmacy refill request with medication details and pharmacy selection",
          category: "healthcare",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Patient Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Insurance ID / Member #" }, { type: :input, width: "half", label: "Insurance Provider" }],
            [{ type: :divider }],
            [{ type: :section, label: "Medication Details" }],
            [{ type: :input, width: "half", label: "Medication Name" }, { type: :input, width: "half", label: "Strength / Dosage" }],
            [{ type: :number, width: "half", label: "Quantity Requested" }, { type: :number, width: "half", label: "Refill Number" }],
            [{ type: :input, width: "half", label: "Prescribing Physician" }, { type: :input, width: "half", label: "Prescription Number (Rx #)" }],
            [{ type: :date, width: "half", label: "Date of Last Fill" }, { type: :select, width: "half", label: "Days Supply (30, 60, 90)" }],
            [{ type: :radio, width: "full", label: "Are you experiencing any new side effects?" }],
            [{ type: :textarea, width: "full", label: "Describe Side Effects (if yes)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Pharmacy & Notes" }],
            [{ type: :select, width: "half", label: "Preferred Pharmacy" }, { type: :select, width: "half", label: "Pickup or Delivery?" }],
            [{ type: :input, width: "full", label: "Delivery Address (if requesting delivery)" }],
            [{ type: :textarea, width: "full", label: "Additional Notes or Questions for the Pharmacist" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Patient Info", match_types: %w[text email tel date] },
              { label: "Medication Details", match_types: %w[number radio date select url] },
              { label: "Pharmacy & Notes", match_types: %w[textarea] }
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
