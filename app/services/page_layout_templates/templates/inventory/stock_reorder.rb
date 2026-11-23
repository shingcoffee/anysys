# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Inventory
      module StockReorder
        DEFINITION = {
          key: "stock_reorder_request",
          name: "Stock Reorder Request",
          description: "Internal stock replenishment request with item details, quantities, vendor preference, and urgency level",
          category: "inventory",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Requester Information" }],
            [{ type: :input, width: "half", label: "Requested By" }, { type: :input, width: "half", label: "Department" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :date, width: "half", label: "Request Date" }],
            [{ type: :input, width: "half", label: "Approving Manager" }, { type: :select, width: "half", label: "Budget / Cost Center Code" }],
            [{ type: :divider }],
            [{ type: :section, label: "Item Details — Line 1" }],
            [{ type: :input, width: "half", label: "SKU / Item Code" }, { type: :input, width: "half", label: "Item Name / Description" }],
            [{ type: :number, width: "half", label: "Current Stock Level" }, { type: :number, width: "half", label: "Reorder Quantity" }],
            [{ type: :input, width: "half", label: "Unit of Measure" }, { type: :number, width: "half", label: "Estimated Unit Cost ($)" }],
            [{ type: :select, width: "half", label: "Preferred Vendor" }, { type: :input, width: "half", label: "Vendor Part Number (if known)" }],
            [{ type: :section, label: "Item Details — Line 2 (optional)" }],
            [{ type: :input, width: "half", label: "SKU / Item Code" }, { type: :input, width: "half", label: "Item Name / Description" }],
            [{ type: :number, width: "half", label: "Current Stock Level" }, { type: :number, width: "half", label: "Reorder Quantity" }],
            [{ type: :divider }],
            [{ type: :section, label: "Urgency & Delivery" }],
            [{ type: :select, width: "half", label: "Urgency (Emergency, High, Normal, Low)" }, { type: :date, width: "half", label: "Needed By Date" }],
            [{ type: :select, width: "half", label: "Delivery Location / Warehouse" }, { type: :radio, width: "half", label: "Is this an emergency reorder?" }],
            [{ type: :textarea, width: "full", label: "Justification or Additional Notes" }],
            [{ type: :checkbox, width: "full", label: "I confirm this request has been approved per procurement policy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "number" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Requester Info", match_types: %w[text email date] },
              { label: "Item & Order Details", match_types: %w[number select radio] },
              { label: "Justification", match_types: %w[textarea checkbox] }
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
