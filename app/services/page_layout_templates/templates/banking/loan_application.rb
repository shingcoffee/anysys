# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Banking
      module LoanApplication
        DEFINITION = {
          key: "loan_application",
          name: "Loan Application",
          description: "Personal or business loan application with financial details and employment",
          category: "banking",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Personal Info" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :input, width: "half", label: "Social Security # (Last 4 Digits)" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Current Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :select, width: "half", label: "Housing Status (Own, Rent, Other)" }, { type: :select, width: "half", label: "Marital Status" }],
            [{ type: :divider }],
            [{ type: :section, label: "Employment & Finances" }],
            [{ type: :select, width: "half", label: "Employment Status (Employed, Self-Employed, Retired, Student, Other)" }, { type: :input, width: "half", label: "Employer Name" }],
            [{ type: :input, width: "half", label: "Job Title / Position" }, { type: :number, width: "half", label: "Years Employed" }],
            [{ type: :number, width: "half", label: "Gross Annual Income ($)" }, { type: :number, width: "half", label: "Other Income ($ - if applicable)" }],
            [{ type: :number, width: "half", label: "Monthly Housing Payment ($)" }, { type: :number, width: "half", label: "Other Monthly Debt Payments ($)" }],
            [{ type: :select, width: "half", label: "Loan Type (Personal, Auto, Home, Business, Student, Debt Consolidation)" }, { type: :number, width: "half", label: "Loan Amount Requested ($)" }],
            [{ type: :select, width: "half", label: "Desired Loan Term (Years / Months)" }, { type: :select, width: "half", label: "Purpose of Loan" }],
            [{ type: :radio, width: "full", label: "Do you have any other outstanding loans?" }],
            [{ type: :radio, width: "full", label: "Have you filed for bankruptcy in the past 7 years?" }],
            [{ type: :radio, width: "full", label: "Will there be a co-applicant or co-signer?" }],
            [{ type: :input, width: "half", label: "Co-Applicant Full Name (if yes)" }, { type: :input, width: "half", label: "Co-Applicant Relationship" }],
            [{ type: :radio, width: "full", label: "Is this a secured loan with collateral?" }],
            [{ type: :select, width: "half", label: "Collateral Type (Vehicle, Property, Savings, Other)" }, { type: :number, width: "half", label: "Estimated Collateral Value ($)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Loan & Documents" }],
            [{ type: :textarea, width: "full", label: "Detailed Loan Purpose / How Funds Will Be Used" }],
            [{ type: :file, width: "full", label: "Upload Supporting Documents (Pay Stubs, Tax Returns, Bank Statements, ID, Other)" }],
            [{ type: :checkbox, width: "full", label: "I authorize a credit check and verification of all information provided" }],
            [{ type: :checkbox, width: "full", label: "I certify that all information is accurate and complete to the best of my knowledge" }]
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
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Personal Info", match_types: %w[text email tel date] },
              { label: "Employment & Finances", match_types: %w[number select radio] },
              { label: "Loan & Documents", match_types: %w[textarea file checkbox] }
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
