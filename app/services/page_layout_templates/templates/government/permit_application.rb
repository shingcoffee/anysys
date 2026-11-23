# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Government
      module PermitApplication
        DEFINITION = {
          key: "permit_application",
          name: "Permit Application",
          description: "Government permit or license application with documentation upload",
          category: "government",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Applicant Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Mailing Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :input, width: "half", label: "Government ID Number" }, { type: :select, width: "half", label: "ID Type (Driver's License, Passport, State ID)" }],
            [{ type: :input, width: "half", label: "Applicant Type (Individual, Business, Organization)" }, { type: :input, width: "half", label: "Business / Organization Name (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Permit Details" }],
            [{ type: :select, width: "half", label: "Permit Type (Building, Business License, Event, Special Use, Zoning Variance, Other)" }, { type: :select, width: "half", label: "Purpose / Activity" }],
            [{ type: :input, width: "full", label: "Property Address / Location of Activity" }],
            [{ type: :date, width: "half", label: "Requested Start Date" }, { type: :date, width: "half", label: "Requested End Date" }],
            [{ type: :textarea, width: "full", label: "Project / Activity Description" }],
            [{ type: :number, width: "half", label: "Estimated Project Cost ($)" }, { type: :number, width: "half", label: "Estimated Occupancy / Attendance" }],
            [{ type: :radio, width: "full", label: "Have you applied for this permit before?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Documentation" }],
            [{ type: :file, width: "full", label: "Upload Supporting Documents (Plans, Drawings, Licenses, Insurance)" }],
            [{ type: :checkbox, width: "full", label: "I certify all information provided is accurate and complete" }],
            [{ type: :checkbox, width: "full", label: "I understand applicable fees may apply and will comply with all permit conditions" }],
            [{ type: :signature, width: "full", label: "Applicant Signature" }]
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
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "file" => "full",
            },
            sections: [
              { label: "Applicant Info", match_types: %w[text email tel date select] },
              { label: "Permit Details", match_types: %w[number textarea radio] },
              { label: "Documentation", match_types: %w[file checkbox] }
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
