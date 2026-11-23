# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Security
      module AccessCardRequest
        DEFINITION = {
          key: "access_card_request",
          name: "Access Card Request",
          description: "Employee or contractor badge and access card request with clearance level and areas",
          category: "security",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Employee Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Employee / Contractor ID" }],
            [{ type: :input, width: "half", label: "Department" }, { type: :input, width: "half", label: "Job Title" }],
            [{ type: :input, width: "half", label: "Direct Manager" }, { type: :input, width: "half", label: "Manager Email" }],
            [{ type: :input, width: "half", label: "Work Email" }, { type: :input, width: "half", label: "Work Phone" }],
            [{ type: :select, width: "half", label: "Employment Type (Full-Time, Part-Time, Contractor, Intern, Visitor)" }, { type: :date, width: "half", label: "Employment / Contract Start Date" }],
            [{ type: :divider }],
            [{ type: :section, label: "Access Details" }],
            [{ type: :select, width: "half", label: "Request Type (New Card, Replacement, Upgrade, Temporary, Deactivate)" }, { type: :select, width: "half", label: "Clearance Level (Public, General, Restricted, Confidential, Top Secret)" }],
            [{ type: :checkbox, width: "full", label: "Areas Requiring Access (Main Lobby, Office Floors, Server Room, Lab, Parking Garage, Executive Suite, Loading Dock, All Areas)" }],
            [{ type: :date, width: "half", label: "Access Start Date" }, { type: :date, width: "half", label: "Access End Date (if temporary)" }],
            [{ type: :radio, width: "full", label: "Is this request approved by department head?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Justification & Upload" }],
            [{ type: :textarea, width: "full", label: "Business Justification for Access" }],
            [{ type: :file, width: "full", label: "Upload Government-Issued ID Photo" }],
            [{ type: :checkbox, width: "full", label: "I acknowledge and agree to comply with all security policies and access control procedures" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Employee Info", match_types: %w[text email tel] },
              { label: "Access Details", match_types: %w[select date checkbox radio] },
              { label: "Justification & Upload", match_types: %w[textarea file] }
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
