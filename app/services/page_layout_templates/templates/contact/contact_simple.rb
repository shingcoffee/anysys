# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Contact
      module ContactSimple
        DEFINITION = {
          key: "contact_simple",
          name: "Simple Contact",
          description: "Quick contact form — name, email, and message",
          category: "contact",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Info" }],
            [{ type: :input, width: "half", label: "Name" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :select, width: "half", label: "Inquiry Type (General, Support, Sales, Other)" }],
            [{ type: :input, width: "full", label: "Subject" }],
            [{ type: :divider }],
            [{ type: :section, label: "Message" }],
            [{ type: :textarea, width: "full", label: "Message" }],
            [{ type: :checkbox, width: "full", label: "I agree to be contacted about my inquiry" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "textarea" => "full",
              "checkbox" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel select] },
              { label: "Message", match_types: %w[textarea checkbox] }
            ],
            inject_elements: [
              { after_section: 0, type: "divider" }
            ]
          }
        }.freeze
      end
    end
  end
end
