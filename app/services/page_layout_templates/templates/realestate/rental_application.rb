# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Realestate
      module RentalApplication
        DEFINITION = {
          key: "rental_application",
          name: "Rental Application",
          description: "Tenant application with employment, references, and income verification",
          category: "realestate",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Applicant Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :input, width: "full", label: "Current Address" }],
            [{ type: :select, width: "half", label: "Current Living Situation" }, { type: :input, width: "half", label: "How long at current address?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Employment & Income" }],
            [{ type: :input, width: "half", label: "Employer Name" }, { type: :input, width: "half", label: "Employer Phone" }],
            [{ type: :input, width: "half", label: "Job Title" }, { type: :input, width: "half", label: "Employment Duration" }],
            [{ type: :number, width: "half", label: "Monthly Gross Income ($)" }, { type: :select, width: "half", label: "Employment Type (Full-time, Part-time, Self-Employed, Other)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Tenancy Details" }],
            [{ type: :date, width: "half", label: "Desired Move-in Date" }, { type: :select, width: "half", label: "Lease Term Preference" }],
            [{ type: :number, width: "half", label: "Number of Occupants" }, { type: :radio, width: "half", label: "Do you have pets?" }],
            [{ type: :input, width: "full", label: "Pet Description (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "References & Documents" }],
            [{ type: :input, width: "half", label: "Reference 1 (Name & Phone)" }, { type: :input, width: "half", label: "Reference 2 (Name & Phone)" }],
            [{ type: :file, width: "full", label: "Government-Issued ID" }],
            [{ type: :file, width: "full", label: "Proof of Income (Pay stubs, Bank statements)" }],
            [{ type: :checkbox, width: "full", label: "I authorize a credit and background check" }]
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
              "textarea" => "full",
              "checkbox" => "full",
              "file" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Personal & Current Housing", match_types: %w[text email tel date select] },
              { label: "Employment & Tenancy", match_types: %w[number radio] },
              { label: "References & Documents", match_types: %w[file checkbox] }
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
