# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Application
      module EmployeeOnboarding
        DEFINITION = {
          key: "employee_onboarding",
          name: "Employee Onboarding",
          description: "New hire form with emergency contacts and policy agreements",
          category: "application",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Middle Name / Initial" }, { type: :input, width: "half", label: "Preferred Name / Nickname" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Home Address (Street)" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :input, width: "half", label: "Social Security # (Last 4 Digits)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Selections" }],
            [{ type: :input, width: "half", label: "Job Title / Position" }, { type: :input, width: "half", label: "Department" }],
            [{ type: :date, width: "half", label: "Start Date / First Day" }, { type: :select, width: "half", label: "Employment Type (Full-Time, Part-Time, Contract)" }],
            [{ type: :input, width: "half", label: "Manager / Supervisor Name" }, { type: :input, width: "half", label: "Work Location / Office" }],
            [{ type: :select, width: "half", label: "Work Schedule (Mon-Fri, Shifts, Hybrid, Remote)" }, { type: :number, width: "half", label: "Hours Per Week" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Relationship to Employee" }],
            [{ type: :input, width: "half", label: "Emergency Phone Number" }, { type: :input, width: "half", label: "Emergency Email (optional)" }],
            [{ type: :select, width: "half", label: "Federal W-4 Filing Status" }, { type: :number, width: "half", label: "Federal Withholding Allowances" }],
            [{ type: :input, width: "half", label: "Bank Name" }, { type: :select, width: "half", label: "Account Type (Checking, Savings)" }],
            [{ type: :input, width: "half", label: "Bank Routing Number" }, { type: :input, width: "half", label: "Bank Account Number" }],
            [{ type: :radio, width: "full", label: "I authorize direct deposit of my paycheck" }],
            [{ type: :select, width: "full", label: "I am authorized to work in the U.S. as (Citizen, Permanent Resident, Work Visa Holder)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Agreements & Notes" }],
            [{ type: :checkbox, width: "full", label: "I-9 Documents Provided (U.S. Passport, Driver's License + SSN Card, Green Card, EAD, Other)" }],
            [{ type: :file, width: "full", label: "Upload I-9 Supporting Documents (ID Copies)" }],
            [{ type: :checkbox, width: "full", label: "I have read and agree to the Employee Handbook, Code of Conduct, NDA, IT Acceptable Use Policy, Drug-Free Workplace Policy, and Anti-Harassment Policy" }],
            [{ type: :signature, width: "full", label: "Employee Signature" }],
            [{ type: :date, width: "half", label: "Signature Date" }, { type: :input, width: "half", label: "Employee ID (Assigned by HR)" }]
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
              "textarea" => "full",
              "file" => "full",
            },
            sections: [
              { label: "Employee Information", match_types: %w[text email tel date url] },
              { label: "Selections", match_types: %w[select number radio] },
              { label: "Agreements & Notes", match_types: %w[checkbox file] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
