# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hr
      module ExpenseReimbursement
        DEFINITION = {
          key: "expense_reimbursement",
          name: "Expense Reimbursement",
          description: "Employee expense claim with receipts and approval workflow",
          category: "hr",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Employee Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :select, width: "half", label: "Department" }],
            [{ type: :input, width: "half", label: "Manager Name" }, { type: :date, width: "half", label: "Submission Date" }],
            [{ type: :input, width: "half", label: "Cost Center / Project Code" }, { type: :select, width: "half", label: "Reimbursement Method (Direct Deposit, Check)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Expense Details" }],
            [{ type: :select, width: "half", label: "Category (Travel, Meals, Lodging, Office Supplies, Software, Client Entertainment, Other)" }, { type: :date, width: "half", label: "Expense Date (Item 1)" }],
            [{ type: :input, width: "half", label: "Vendor / Description (Item 1)" }, { type: :number, width: "half", label: "Amount $ (Item 1)" }],
            [{ type: :select, width: "half", label: "Payment Method (Personal Card, Cash, Company Card)" }, { type: :file, width: "half", label: "Receipt (Item 1)" }],
            [{ type: :select, width: "half", label: "Category (Item 2)" }, { type: :date, width: "half", label: "Expense Date (Item 2)" }],
            [{ type: :input, width: "half", label: "Vendor / Description (Item 2)" }, { type: :number, width: "half", label: "Amount $ (Item 2)" }],
            [{ type: :select, width: "half", label: "Payment Method (Item 2)" }, { type: :file, width: "half", label: "Receipt (Item 2)" }],
            [{ type: :number, width: "half", label: "Total Reimbursement Requested ($)" }, { type: :select, width: "half", label: "Currency" }],
            [{ type: :divider }],
            [{ type: :section, label: "Summary & Certification" }],
            [{ type: :textarea, width: "full", label: "Business Purpose / Justification for Expenses" }],
            [{ type: :checkbox, width: "full", label: "I certify these expenses are accurate, business-related, have supporting receipts, and have not been previously submitted" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "date" => "half",
              "number" => "half",
              "file" => "half",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Employee Info", match_types: %w[text email tel select date] },
              { label: "Expense Details", match_types: %w[number file] },
              { label: "Summary & Certification", match_types: %w[textarea checkbox] }
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
