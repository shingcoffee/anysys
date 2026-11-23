# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Manufacturing
      module WorkOrder
        DEFINITION = {
          key: "work_order",
          name: "Work Order",
          description: "Production or maintenance work order with tasks, materials, and timeline",
          category: "manufacturing",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Work Order Header" }],
            [{ type: :input, width: "half", label: "Work Order #" }, { type: :date, width: "half", label: "Date Issued" }],
            [{ type: :input, width: "half", label: "Requested By" }, { type: :select, width: "half", label: "Priority (Low, Normal, High, Critical)" }],
            [{ type: :select, width: "half", label: "Work Order Type (Production, Maintenance, Repair, Installation, Inspection)" }, { type: :select, width: "half", label: "Department" }],
            [{ type: :input, width: "half", label: "Supervisor / Approver" }, { type: :input, width: "half", label: "Cost Center / Budget Code" }],
            [{ type: :divider }],
            [{ type: :section, label: "Work Details" }],
            [{ type: :input, width: "half", label: "Machine / Asset / Location" }, { type: :input, width: "half", label: "Asset Tag #" }],
            [{ type: :textarea, width: "full", label: "Description of Work Required" }],
            [{ type: :textarea, width: "full", label: "Materials / Parts Required (Part #, Qty, Description)" }],
            [{ type: :date, width: "half", label: "Scheduled Start Date" }, { type: :date, width: "half", label: "Due Date" }],
            [{ type: :input, width: "half", label: "Assigned Technician / Team" }, { type: :number, width: "half", label: "Estimated Hours" }],
            [{ type: :divider }],
            [{ type: :section, label: "Safety & Completion" }],
            [{ type: :textarea, width: "full", label: "Safety Precautions & PPE Requirements" }],
            [{ type: :checkbox, width: "full", label: "Safety checks: Lockout/Tagout, PPE, Fire Extinguisher, Hazardous Materials Handling" }],
            [{ type: :textarea, width: "full", label: "Completion Notes / Work Performed" }],
            [{ type: :number, width: "half", label: "Actual Hours Spent" }, { type: :date, width: "half", label: "Completion Date" }],
            [{ type: :radio, width: "full", label: "Was work completed as specified?" }],
            [{ type: :signature, width: "full", label: "Technician Sign-Off" }]
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
              "checkbox" => "full",
            },
            sections: [
              { label: "Order Header", match_types: %w[text date select] },
              { label: "Work Scope", match_types: %w[number textarea] },
              { label: "Safety & Completion", match_types: %w[checkbox radio] }
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
