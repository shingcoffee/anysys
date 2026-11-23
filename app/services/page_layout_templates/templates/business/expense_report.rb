# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Business
      module ExpenseReport
        DEFINITION = {
          key: "expense_report",
          name: "Expense Report",
          description: "Employee expense claim with receipt upload and approval routing",
          category: "business",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Employee & Period" }],
            [{ type: :input, width: "half", label: "Employee Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :select, width: "half", label: "Department" }],
            [{ type: :input, width: "half", label: "Manager / Approver Name" }, { type: :input, width: "half", label: "Cost Center / Project Code" }],
            [{ type: :date, width: "half", label: "Report Period Start Date" }, { type: :date, width: "half", label: "Report Period End Date" }],
            [{ type: :select, width: "half", label: "Preferred Reimbursement Method (Direct Deposit, Check, Payroll)" }, { type: :select, width: "half", label: "Currency" }],
            [{ type: :divider }],
            [{ type: :section, label: "Expense Items" }],
            [{ type: :input, width: "full", label: "Expense Description (Line 1)" }],
            [{ type: :select, width: "third", label: "Category (Meals, Travel, Lodging, Office, Other)" }, { type: :date, width: "third", label: "Date" }, { type: :number, width: "third", label: "Amount ($)" }],
            [{ type: :select, width: "half", label: "Payment Method (Corporate Card, Personal, Cash)" }, { type: :input, width: "half", label: "Vendor / Merchant Name" }],
            [{ type: :input, width: "full", label: "Expense Description (Line 2)" }],
            [{ type: :select, width: "third", label: "Category" }, { type: :date, width: "third", label: "Date" }, { type: :number, width: "third", label: "Amount ($)" }],
            [{ type: :select, width: "half", label: "Payment Method" }, { type: :input, width: "half", label: "Vendor / Merchant Name" }],
            [{ type: :input, width: "full", label: "Expense Description (Line 3)" }],
            [{ type: :select, width: "third", label: "Category" }, { type: :date, width: "third", label: "Date" }, { type: :number, width: "third", label: "Amount ($)" }],
            [{ type: :select, width: "half", label: "Payment Method" }, { type: :input, width: "half", label: "Vendor / Merchant Name" }],
            [{ type: :number, width: "half", label: "Total Expenses ($)" }, { type: :number, width: "half", label: "Total Reimbursable ($)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Receipts & Notes" }],
            [{ type: :file, width: "full", label: "Upload Receipts (All Lines)" }],
            [{ type: :textarea, width: "full", label: "Business Purpose / Additional Notes or Explanations" }],
            [{ type: :checkbox, width: "full", label: "I certify all expenses are accurate, business-related, and compliant with company expense policy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "number" => "half",
              "date" => "half",
              "select" => "half",
              "checkbox" => "full",
              "file" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Employee & Period", match_types: %w[text email tel date] },
              { label: "Expense Items", match_types: %w[number select] },
              { label: "Receipts & Notes", match_types: %w[file textarea checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
