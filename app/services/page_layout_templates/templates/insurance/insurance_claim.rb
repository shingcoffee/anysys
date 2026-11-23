# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Insurance
      module InsuranceClaim
        DEFINITION = {
          key: "insurance_claim",
          name: "Insurance Claim",
          description: "File an insurance claim with incident details, photos, and documentation",
          category: "insurance",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Policyholder Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Policy Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Mailing Address" }],
            [{ type: :date, width: "half", label: "Date Policy Was Issued" }, { type: :input, width: "half", label: "Insurance Agent Name (if known)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Incident Details" }],
            [{ type: :select, width: "half", label: "Claim Type (Auto, Property, Medical, Liability, Theft, Natural Disaster, Other)" }, { type: :date, width: "half", label: "Date of Incident" }],
            [{ type: :input, width: "full", label: "Location of Incident" }],
            [{ type: :textarea, width: "full", label: "Describe What Happened (be as detailed as possible)" }],
            [{ type: :number, width: "half", label: "Estimated Damage / Loss Amount ($)" }, { type: :select, width: "half", label: "Severity (Minor, Moderate, Major, Total Loss)" }],
            [{ type: :radio, width: "full", label: "Was a police / fire report filed?" }],
            [{ type: :input, width: "half", label: "Police / Fire Report Number (if applicable)" }, { type: :input, width: "half", label: "Other Parties Involved (Names & Contact)" }],
            [{ type: :radio, width: "full", label: "Were there any witnesses?" }],
            [{ type: :textarea, width: "full", label: "Witness Information (Name, Phone, Statement)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Documentation" }],
            [{ type: :file, width: "full", label: "Upload Photos or Videos of Damage / Incident" }],
            [{ type: :file, width: "full", label: "Upload Supporting Documents (Receipts, Medical Records, Repair Estimates)" }],
            [{ type: :checkbox, width: "full", label: "I certify the above information is true and accurate to the best of my knowledge" }]
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
              "file" => "full"
            },
            sections: [
              { label: "Policyholder Info", match_types: %w[text email tel] },
              { label: "Incident Details", match_types: %w[select date number radio textarea] },
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
