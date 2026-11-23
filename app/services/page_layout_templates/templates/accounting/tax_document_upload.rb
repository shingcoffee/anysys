# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Accounting
      module TaxDocumentUpload
        DEFINITION = {
          key: "tax_document_upload",
          name: "Tax Document Upload",
          description: "Secure tax document submission portal with document type classification and notes",
          category: "accounting",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Client Information" }],
            [{ type: :input, width: "half", label: "Client Name / Business Name" }, { type: :input, width: "half", label: "Client ID / Account Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Social Security # or EIN (Last 4 digits)" }, { type: :select, width: "half", label: "Entity Type (Individual, LLC, S-Corp, Partnership, Trust)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Document Details" }],
            [{ type: :select, width: "half", label: "Tax Year" }, { type: :select, width: "half", label: "Filing Type (Individual, Business, Partnership, Trust)" }],
            [{ type: :select, width: "half", label: "Filing Status (Single, Married Filing Joint, Married Filing Separate, Head of Household)" }, { type: :select, width: "half", label: "State(s) Filing Required" }],
            [{ type: :date, width: "half", label: "Tax Return Due Date" }, { type: :radio, width: "half", label: "Extension Filed?" }],
            [{ type: :checkbox, width: "full", label: "Documents Included (W-2, 1099s, K-1, 1098 Mortgage, 1098-T Education, Investment Statements, Charitable Receipts, Medical Expenses, Business Receipts, Property Tax, Retirement Contributions, Prior Year Return)" }],
            [{ type: :file, width: "full", label: "Upload Tax Documents (PDF, JPG, PNG — Max 25MB per file)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Notes & Confirmation" }],
            [{ type: :radio, width: "full", label: "Any major life changes this year? (Marriage, Divorce, Birth, Home Purchase, New Business, Job Change)" }],
            [{ type: :textarea, width: "full", label: "Notes for Your Accountant / Special Circumstances" }],
            [{ type: :select, width: "half", label: "Preferred Delivery of Completed Return (Email, Portal, Mail)" }, { type: :date, width: "half", label: "Date Submitted" }],
            [{ type: :checkbox, width: "full", label: "I confirm all documents are complete, accurate, and legible" }],
            [{ type: :checkbox, width: "full", label: "I authorize my accountant to file my return electronically on my behalf" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "file" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Client Info", match_types: %w[text email tel] },
              { label: "Document Details", match_types: %w[select date radio checkbox file] },
              { label: "Notes & Confirmation", match_types: %w[textarea] }
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
