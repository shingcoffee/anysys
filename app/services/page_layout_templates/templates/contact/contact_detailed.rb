# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Contact
      module ContactDetailed
        DEFINITION = {
          key: "contact_detailed",
          name: "Detailed Contact",
          description: "Full contact form with phone, company, and department selector",
          category: "contact",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Your Information" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Email" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :input, width: "half", label: "Job Title" }, { type: :input, width: "half", label: "Company" }],
            [{ type: :select, width: "half", label: "Department" }, { type: :select, width: "half", label: "Preferred Contact Method (Email, Phone, Either)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Message" }],
            [{ type: :select, width: "half", label: "Inquiry Type (General, Sales, Support, Billing, Partnership, Other)" }, { type: :select, width: "half", label: "Urgency (Normal, High, Urgent)" }],
            [{ type: :input, width: "full", label: "Subject" }],
            [{ type: :textarea, width: "full", label: "Message" }],
            [{ type: :file, width: "full", label: "Attachments (Optional)" }],
            [{ type: :checkbox, width: "full", label: "I consent to being contacted regarding my inquiry" }]
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
              "file" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Your Information", match_types: %w[text email tel select] },
              { label: "Your Message", match_types: %w[textarea checkbox file] }
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
