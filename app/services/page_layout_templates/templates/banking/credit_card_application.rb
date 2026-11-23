# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Banking
      module CreditCardApplication
        DEFINITION = {
          key: "credit_card_application",
          name: "Credit Card Application",
          description: "Credit card application with personal, employment, and financial information",
          category: "banking",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Personal Info" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Middle Initial" }],
            [{ type: :input, width: "half", label: "Last Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number (Primary)" }],
            [{ type: :input, width: "half", label: "Mobile Phone" }, { type: :input, width: "half", label: "Social Security Number (Last 4 Digits)" }],
            [{ type: :input, width: "full", label: "Current Home Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :select, width: "half", label: "Housing Status (Own, Rent, Other)" }, { type: :number, width: "half", label: "Monthly Rent / Mortgage Payment ($)" }],
            [{ type: :select, width: "half", label: "Residency Status (Citizen, Permanent Resident, Visa Holder)" }, { type: :number, width: "half", label: "Years at Current Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Employment & Income" }],
            [{ type: :select, width: "half", label: "Employment Status (Employed, Self-Employed, Retired, Student, Other)" }, { type: :input, width: "half", label: "Employer Name / Business" }],
            [{ type: :input, width: "half", label: "Job Title / Occupation" }, { type: :number, width: "half", label: "Years with Current Employer" }],
            [{ type: :input, width: "full", label: "Employer Address" }],
            [{ type: :input, width: "half", label: "Employer Phone" }, { type: :number, width: "half", label: "Annual Gross Income ($)" }],
            [{ type: :number, width: "half", label: "Other Annual Income ($)" }, { type: :input, width: "half", label: "Source of Other Income (if any)" }],
            [{ type: :number, width: "half", label: "Total Monthly Debt Payments ($)" }, { type: :number, width: "half", label: "Total Credit Card Debt ($)" }],
            [{ type: :radio, width: "full", label: "Have you declared bankruptcy in the past 7 years?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Agreement" }],
            [{ type: :select, width: "half", label: "Card Type Requested (Rewards, Cash Back, Travel, Balance Transfer, Secured)" }, { type: :select, width: "half", label: "Requested Credit Limit ($)" }],
            [{ type: :radio, width: "full", label: "Are you an existing bank customer?" }],
            [{ type: :input, width: "half", label: "Existing Account Number (if applicable)" }, { type: :input, width: "half", label: "Authorized User Name (if adding one)" }],
            [{ type: :checkbox, width: "full", label: "I authorize the bank to obtain my credit report and certify all information provided is accurate and complete" }],
            [{ type: :checkbox, width: "full", label: "I have read and agree to the Terms and Conditions, Privacy Policy, and electronic communications" }],
            [{ type: :signature, width: "full", label: "Applicant Signature" }],
            [{ type: :date, width: "half", label: "Signature Date" }, { type: :input, width: "half", label: "Application Reference # (auto-generated)" }]
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
              "checkbox" => "full",
            },
            sections: [
              { label: "Personal Info", match_types: %w[text email tel date] },
              { label: "Employment & Income", match_types: %w[select number radio] },
              { label: "Agreement", match_types: %w[checkbox] }
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
