# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Procurement
      module PurchaseOrder
        DEFINITION = {
          key: "purchase_order",
          name: "Purchase Order",
          description: "Procurement purchase order with vendor, items, quantities, and approval",
          category: "procurement",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Order Information" }],
            [{ type: :input, width: "half", label: "PO Number" }, { type: :date, width: "half", label: "Issue Date" }],
            [{ type: :input, width: "half", label: "Requester Name" }, { type: :select, width: "half", label: "Department" }],
            [{ type: :input, width: "half", label: "Approver Name" }, { type: :input, width: "half", label: "Cost Center / Budget Code" }],
            [{ type: :divider }],
            [{ type: :section, label: "Vendor Information" }],
            [{ type: :input, width: "half", label: "Vendor Name" }, { type: :input, width: "half", label: "Vendor Contact" }],
            [{ type: :input, width: "half", label: "Vendor Email" }, { type: :input, width: "half", label: "Vendor Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Line Items" }],
            [{ type: :input, width: "half", label: "Item 1 Description" }, { type: :number, width: "half", label: "Qty 1" }],
            [{ type: :number, width: "half", label: "Unit Price 1 ($)" }, { type: :number, width: "half", label: "Line Total 1 ($)" }],
            [{ type: :input, width: "half", label: "Item 2 Description" }, { type: :number, width: "half", label: "Qty 2" }],
            [{ type: :number, width: "half", label: "Unit Price 2 ($)" }, { type: :number, width: "half", label: "Line Total 2 ($)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Terms & Delivery" }],
            [{ type: :select, width: "half", label: "Payment Terms (Net 30, Net 60, COD, Prepaid)" }, { type: :date, width: "half", label: "Required Delivery Date" }],
            [{ type: :input, width: "full", label: "Delivery Address" }],
            [{ type: :textarea, width: "full", label: "Special Instructions or Notes" }],
            [{ type: :checkbox, width: "full", label: "Budget has been approved for this purchase" }]
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
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Order & Vendor Info", match_types: %w[text email tel date select] },
              { label: "Line Items", match_types: %w[number] },
              { label: "Terms & Approval", match_types: %w[textarea checkbox] }
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
