# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Retail
      module InventoryCount
        DEFINITION = {
          key: "inventory_count",
          name: "Inventory Count",
          description: "Physical inventory audit with product counts, discrepancies, and location",
          category: "retail",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Count Session Information" }],
            [{ type: :input, width: "half", label: "Store / Location" }, { type: :date, width: "half", label: "Count Date" }],
            [{ type: :input, width: "half", label: "Counter Name" }, { type: :input, width: "half", label: "Counter Employee ID" }],
            [{ type: :select, width: "half", label: "Department / Section" }, { type: :select, width: "half", label: "Count Type (Full, Cycle, Spot Check)" }],
            [{ type: :input, width: "half", label: "Supervisor / Approver Name" }, { type: :select, width: "half", label: "Shift" }],
            [{ type: :divider }],
            [{ type: :section, label: "Item Count — Entry 1" }],
            [{ type: :input, width: "half", label: "SKU / Barcode" }, { type: :input, width: "half", label: "Product Name" }],
            [{ type: :number, width: "half", label: "Expected Qty" }, { type: :number, width: "half", label: "Actual Qty" }],
            [{ type: :select, width: "half", label: "Condition (New, Good, Damaged, Expired)" }, { type: :input, width: "half", label: "Location / Shelf / Bin" }],
            [{ type: :section, label: "Item Count — Entry 2" }],
            [{ type: :input, width: "half", label: "SKU / Barcode" }, { type: :input, width: "half", label: "Product Name" }],
            [{ type: :number, width: "half", label: "Expected Qty" }, { type: :number, width: "half", label: "Actual Qty" }],
            [{ type: :select, width: "half", label: "Condition" }, { type: :input, width: "half", label: "Location / Shelf / Bin" }],
            [{ type: :divider }],
            [{ type: :section, label: "Discrepancy & Notes" }],
            [{ type: :radio, width: "full", label: "Were any discrepancies found?" }],
            [{ type: :textarea, width: "full", label: "Discrepancy Notes / Explanation" }],
            [{ type: :file, width: "full", label: "Supporting Photos" }],
            [{ type: :checkbox, width: "full", label: "I confirm this count is accurate to the best of my knowledge" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Count Info", match_types: %w[text date select] },
              { label: "Product Counts", match_types: %w[number radio] },
              { label: "Notes & Photos", match_types: %w[textarea file checkbox] }
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
