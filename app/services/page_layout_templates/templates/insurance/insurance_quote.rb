# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Insurance
      module InsuranceQuote
        DEFINITION = {
          key: "insurance_quote",
          name: "Insurance Quote Request",
          description: "Insurance quote with coverage type, personal details, and property info",
          category: "insurance",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Applicant Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :select, width: "half", label: "Marital Status" }, { type: :select, width: "half", label: "Employment Status" }],
            [{ type: :divider }],
            [{ type: :section, label: "Coverage Details" }],
            [{ type: :select, width: "half", label: "Insurance Type (Auto, Home, Life, Health, Renters, Business, Other)" }, { type: :select, width: "half", label: "Coverage Level (Basic, Standard, Comprehensive)" }],
            [{ type: :date, width: "half", label: "Desired Start Date" }, { type: :number, width: "half", label: "Desired Coverage Amount ($)" }],
            [{ type: :select, width: "half", label: "Deductible Preference" }, { type: :select, width: "half", label: "Payment Frequency (Monthly, Quarterly, Annual)" }],
            [{ type: :radio, width: "full", label: "Do you have any previous insurance claims in the last 5 years?" }],
            [{ type: :radio, width: "full", label: "Are you currently insured?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Additional Information" }],
            [{ type: :textarea, width: "full", label: "Additional Details (Property info, Vehicle info, Health conditions, etc.)" }],
            [{ type: :checkbox, width: "full", label: "I consent to a background / credit check for underwriting purposes" }]
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
              "checkbox" => "full"
            },
            sections: [
              { label: "Personal Info", match_types: %w[text email tel date select] },
              { label: "Coverage Details", match_types: %w[number radio] },
              { label: "Additional Info", match_types: %w[textarea checkbox] }
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
