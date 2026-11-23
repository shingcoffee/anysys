# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module It
      module EquipmentRequest
        DEFINITION = {
          key: "equipment_request",
          name: "Equipment Request",
          description: "IT equipment or software request with justification and approval",
          category: "it",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Requester Information" }],
            [{ type: :input, width: "half", label: "Requester Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :input, width: "half", label: "Email" }, { type: :select, width: "half", label: "Department" }],
            [{ type: :input, width: "half", label: "Manager Name" }, { type: :date, width: "half", label: "Date Needed By" }],
            [{ type: :divider }],
            [{ type: :section, label: "Equipment Details" }],
            [{ type: :select, width: "half", label: "Request Type (New Purchase, Replacement, Upgrade, Software License)" }, { type: :select, width: "half", label: "Category (Laptop, Desktop, Monitor, Phone, Printer, Accessory, Software, Other)" }],
            [{ type: :input, width: "full", label: "Item Description / Model / Specs" }],
            [{ type: :number, width: "half", label: "Quantity" }, { type: :number, width: "half", label: "Estimated Unit Cost ($)" }],
            [{ type: :radio, width: "full", label: "Replaces existing equipment?" }],
            [{ type: :input, width: "half", label: "Asset Tag of Item Being Replaced (if applicable)" }, { type: :select, width: "half", label: "Vendor Preference (if any)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Justification" }],
            [{ type: :textarea, width: "full", label: "Business Justification & Purpose" }],
            [{ type: :select, width: "half", label: "Budget Code / Cost Center" }, { type: :radio, width: "half", label: "Has budget been approved?" }],
            [{ type: :checkbox, width: "full", label: "I confirm this request has been discussed with my manager" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "date" => "half",
              "number" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Requester Info", match_types: %w[text email tel select date] },
              { label: "Equipment Details", match_types: %w[number radio] },
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
