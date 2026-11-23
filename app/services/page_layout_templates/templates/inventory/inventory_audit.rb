# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Inventory
      module InventoryAudit
        DEFINITION = {
          key: "inventory_audit",
          name: "Inventory Audit Form",
          description: "Warehouse or store inventory audit with item counts, discrepancy reporting, and auditor sign-off",
          category: "inventory",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Audit Session Information" }],
            [{ type: :input, width: "half", label: "Auditor Full Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :date, width: "half", label: "Audit Date" }, { type: :select, width: "half", label: "Location / Warehouse" }],
            [{ type: :select, width: "half", label: "Audit Type (Full, Cycle Count, Spot Check, Year-End)" }, { type: :select, width: "half", label: "Department / Zone / Aisle" }],
            [{ type: :input, width: "half", label: "Supervisor / Approver Name" }, { type: :select, width: "half", label: "Shift" }],
            [{ type: :divider }],
            [{ type: :section, label: "Item Count — Entry 1" }],
            [{ type: :input, width: "half", label: "SKU / Item Code" }, { type: :input, width: "half", label: "Item Description" }],
            [{ type: :number, width: "half", label: "System Count" }, { type: :number, width: "half", label: "Physical Count" }],
            [{ type: :number, width: "half", label: "Variance" }, { type: :select, width: "half", label: "Condition (Good, Damaged, Expired, Misplaced)" }],
            [{ type: :input, width: "half", label: "Bin / Shelf Location" }, { type: :select, width: "half", label: "Unit of Measure" }],
            [{ type: :divider }],
            [{ type: :section, label: "Discrepancy & Sign-off" }],
            [{ type: :radio, width: "full", label: "Were discrepancies found?" }],
            [{ type: :textarea, width: "full", label: "Notes on Discrepancies, Damage, or Observations" }],
            [{ type: :file, width: "full", label: "Photos of Discrepancies or Damaged Items" }],
            [{ type: :checkbox, width: "full", label: "I certify this audit was conducted accurately and completely" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "date" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Auditor & Location", match_types: %w[text date select] },
              { label: "Item Counts", match_types: %w[number radio] },
              { label: "Notes & Evidence", match_types: %w[textarea file checkbox] }
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
