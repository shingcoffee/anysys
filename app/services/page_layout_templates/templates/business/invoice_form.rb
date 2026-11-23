# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Business
      module InvoiceForm
        DEFINITION = {
          key: "invoice_form",
          name: "Invoice / Payment",
          description: "Billing form with itemized amounts and payment info",
          category: "business",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Billing Details" }],
            [{ type: :input, width: "half", label: "Company / Business Name" }, { type: :input, width: "half", label: "Invoice Number" }],
            [{ type: :input, width: "full", label: "Business Address" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "half", label: "Tax ID / EIN" }, { type: :input, width: "half", label: "Website" }],
            [{ type: :input, width: "half", label: "Customer Name / Company" }, { type: :input, width: "half", label: "Customer ID" }],
            [{ type: :input, width: "full", label: "Billing Address" }],
            [{ type: :input, width: "half", label: "Customer Email" }, { type: :input, width: "half", label: "Customer Phone" }],
            [{ type: :date, width: "half", label: "Invoice Date" }, { type: :date, width: "half", label: "Due Date" }],
            [{ type: :select, width: "half", label: "Payment Terms (Net 15, Net 30, Net 60, Due on Receipt)" }, { type: :input, width: "half", label: "PO Number (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Line Items" }],
            [{ type: :input, width: "full", label: "Item Description (Line 1)" }],
            [{ type: :number, width: "third", label: "Quantity" }, { type: :number, width: "third", label: "Unit Price ($)" }, { type: :number, width: "third", label: "Line Total ($)" }],
            [{ type: :input, width: "full", label: "Item Description (Line 2)" }],
            [{ type: :number, width: "third", label: "Quantity" }, { type: :number, width: "third", label: "Unit Price ($)" }, { type: :number, width: "third", label: "Line Total ($)" }],
            [{ type: :input, width: "full", label: "Item Description (Line 3)" }],
            [{ type: :number, width: "third", label: "Quantity" }, { type: :number, width: "third", label: "Unit Price ($)" }, { type: :number, width: "third", label: "Line Total ($)" }],
            [{ type: :number, width: "half", label: "Subtotal ($)" }, { type: :number, width: "half", label: "Discount / Promo ($)" }],
            [{ type: :number, width: "half", label: "Tax Rate (%)" }, { type: :number, width: "half", label: "Tax Amount ($)" }],
            [{ type: :number, width: "half", label: "Shipping / Delivery ($)" }, { type: :number, width: "half", label: "Total Amount Due ($)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Notes" }],
            [{ type: :select, width: "full", label: "Accepted Payment Methods (Check, Wire Transfer, Credit Card, ACH, PayPal)" }],
            [{ type: :textarea, width: "full", label: "Payment Instructions (Bank Account, Mailing Address, Payment Link)" }],
            [{ type: :textarea, width: "full", label: "Notes, Terms & Conditions, Late Fee Policy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "number" => "half",
              "date" => "half",
              "select" => "half",
              "email" => "half",
              "tel" => "half",
              "textarea" => "full"
            },
            sections: [
              { label: "Billing Details", match_types: %w[text email tel date url] },
              { label: "Line Items", match_types: %w[number select] },
              { label: "Notes", match_types: %w[textarea] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
