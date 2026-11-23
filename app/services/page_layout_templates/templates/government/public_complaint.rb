# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Government
      module PublicComplaint
        DEFINITION = {
          key: "public_complaint",
          name: "Public Complaint",
          description: "Citizen complaint or service request with location and tracking",
          category: "government",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Home Address" }],
            [{ type: :select, width: "half", label: "Preferred Contact Method (Email, Phone, Either)" }, { type: :checkbox, width: "half", label: "I wish to remain anonymous (contact info will not be shared)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Complaint Details" }],
            [{ type: :select, width: "half", label: "Complaint Category (Roads, Utilities, Noise, Safety, Zoning, Sanitation, Public Services, Other)" }, { type: :select, width: "half", label: "Department Responsible" }],
            [{ type: :select, width: "half", label: "Priority / Urgency (Low, Normal, High, Emergency)" }, { type: :date, width: "half", label: "Date Issue Was Observed" }],
            [{ type: :input, width: "full", label: "Location of Issue (Address or Nearest Cross Streets)" }],
            [{ type: :textarea, width: "full", label: "Describe the Issue in Detail" }],
            [{ type: :textarea, width: "full", label: "What resolution are you requesting?" }],
            [{ type: :radio, width: "full", label: "Has this issue been reported to us before?" }],
            [{ type: :radio, width: "full", label: "Is this a safety or health emergency?" }],
            [{ type: :file, width: "full", label: "Upload Photos, Videos, or Supporting Evidence" }]
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
              "textarea" => "full",
              "checkbox" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel select] },
              { label: "Complaint Details", match_types: %w[date radio textarea checkbox] },
              { label: "Evidence", match_types: %w[file] }
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
