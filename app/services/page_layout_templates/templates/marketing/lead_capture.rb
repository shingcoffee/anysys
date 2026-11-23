# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Marketing
      module LeadCapture
        DEFINITION = {
          key: "lead_capture",
          name: "Lead Capture",
          description: "High-conversion lead gen — minimal fields for maximum completion",
          category: "marketing",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Your Details" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "full", label: "Work Email" }],
            [{ type: :input, width: "half", label: "Company" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :select, width: "half", label: "Job Title / Role" }, { type: :select, width: "half", label: "Company Size" }],
            [{ type: :select, width: "half", label: "Industry" }, { type: :select, width: "half", label: "What best describes your interest?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Needs" }],
            [{ type: :textarea, width: "full", label: "What is your biggest challenge or goal right now?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Consent" }],
            [{ type: :checkbox, width: "full", label: "I agree to receive communications and understand I can unsubscribe at any time" }],
            [{ type: :checkbox, width: "full", label: "I agree to the privacy policy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "full",
              "tel" => "half",
              "select" => "half",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Your Details", match_types: %w[text email tel select] },
              { label: "Your Needs", match_types: %w[textarea] },
              { label: "Consent", match_types: %w[checkbox] }
            ],
            inject_elements: [
              { after_section: 0, type: "divider" }, { after_section: 2, type: "divider" }
            ]
          }
        }.freeze
      end
    end
  end
end
