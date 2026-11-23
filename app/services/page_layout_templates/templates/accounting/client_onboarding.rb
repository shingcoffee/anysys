# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Accounting
      module ClientOnboarding
        DEFINITION = {
          key: "accounting_client_onboarding",
          name: "Client Onboarding",
          description: "New accounting client intake with business details, tax info, and documents",
          category: "accounting",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Business Information" }],
            [{ type: :input, width: "half", label: "Business / Legal Name" }, { type: :select, width: "half", label: "Entity Type (LLC, Corp, S-Corp, Partnership, Sole Prop)" }],
            [{ type: :input, width: "half", label: "Doing Business As (DBA)" }, { type: :input, width: "half", label: "Federal EIN / Tax ID" }],
            [{ type: :input, width: "half", label: "State Tax ID" }, { type: :date, width: "half", label: "Date Business Established" }],
            [{ type: :input, width: "half", label: "Industry / NAICS Code" }, { type: :number, width: "half", label: "Number of Employees" }],
            [{ type: :input, width: "full", label: "Business Mailing Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :divider }],
            [{ type: :section, label: "Primary Contact" }],
            [{ type: :input, width: "half", label: "Contact Name" }, { type: :input, width: "half", label: "Title / Role" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Mobile Phone" }, { type: :select, width: "half", label: "Preferred Contact Method (Email, Phone, Text)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Services & Financials" }],
            [{ type: :select, width: "half", label: "Fiscal Year End (Month)" }, { type: :select, width: "half", label: "Accounting Basis (Cash, Accrual)" }],
            [{ type: :select, width: "half", label: "Current Accounting Software" }, { type: :select, width: "half", label: "Payroll Provider (if any)" }],
            [{ type: :number, width: "half", label: "Estimated Annual Revenue ($)" }, { type: :number, width: "half", label: "Estimated Annual Expenses ($)" }],
            [{ type: :select, width: "half", label: "Number of Bank Accounts" }, { type: :select, width: "half", label: "Number of Credit Cards" }],
            [{ type: :checkbox, width: "full", label: "Services Required (Bookkeeping, Tax Prep Corporate, Tax Prep Personal, Payroll, Sales Tax, Audit Support, CFO Advisory, Financial Statements, Business Consulting)" }],
            [{ type: :select, width: "half", label: "Preferred Service Frequency (Monthly, Quarterly, Annually)" }, { type: :date, width: "half", label: "Desired Start Date" }],
            [{ type: :divider }],
            [{ type: :section, label: "Documents & Notes" }],
            [{ type: :input, width: "half", label: "Prior Accounting Firm Name" }, { type: :input, width: "half", label: "Prior Accountant Contact" }],
            [{ type: :textarea, width: "full", label: "Reason for Switching / Joining" }],
            [{ type: :radio, width: "full", label: "Are your books currently up-to-date?" }],
            [{ type: :date, width: "half", label: "Last Tax Return Filed (Year)" }, { type: :select, width: "half", label: "Any Outstanding Tax Issues?" }],
            [{ type: :file, width: "full", label: "Prior Year Tax Returns (Last 1-3 Years)" }],
            [{ type: :file, width: "full", label: "Recent Financial Statements (P&L, Balance Sheet)" }],
            [{ type: :textarea, width: "full", label: "Additional Notes, Goals, or Special Requirements" }],
            [{ type: :checkbox, width: "full", label: "I authorize this firm to act on my behalf and access necessary financial records for services rendered" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "number" => "half",
              "date" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Business Details", match_types: %w[text email tel] },
              { label: "Services & Financials", match_types: %w[checkbox select number date radio] },
              { label: "Documents & Notes", match_types: %w[file textarea] }
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
