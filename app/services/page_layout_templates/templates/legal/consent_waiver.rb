# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Legal
      module ConsentWaiver
        DEFINITION = {
          key: "consent_waiver",
          name: "Consent / Waiver",
          description: "Legal consent with terms acknowledgment and signature capture",
          category: "legal",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Personal Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :select, width: "half", label: "Relationship to Participant (Self, Parent / Guardian)" }],
            [{ type: :input, width: "half", label: "Participant Name (if different from above)" }, { type: :date, width: "half", label: "Participant Date of Birth (if minor)" }],
            [{ type: :input, width: "full", label: "Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Waiver Details" }],
            [{ type: :select, width: "half", label: "Activity / Service" }, { type: :date, width: "half", label: "Event / Service Date" }],
            [{ type: :select, width: "half", label: "Location" }, { type: :select, width: "half", label: "Waiver Type (Liability, Media Release, Medical, General)" }],
            [{ type: :textarea, width: "full", label: "Terms and Conditions / Waiver Summary" }],
            [{ type: :divider }],
            [{ type: :section, label: "Acknowledgment & Signature" }],
            [{ type: :checkbox, width: "full", label: "I have read, understood, and agree to all terms and conditions" }],
            [{ type: :checkbox, width: "full", label: "I am 18 years of age or older, or the legal guardian of the participant" }],
            [{ type: :checkbox, width: "full", label: "I acknowledge the inherent risks of this activity and voluntarily release the organization from liability" }],
            [{ type: :signature, width: "full", label: "Signature" }]
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
            },
            sections: [
              { label: "Personal Info", match_types: %w[text email tel date select] },
              { label: "Waiver Details", match_types: %w[textarea] },
              { label: "Acknowledgment & Signature", match_types: %w[checkbox] }
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
