# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Moving
      module StorageRental
        DEFINITION = {
          key: "storage_rental",
          name: "Storage Unit Rental",
          description: "Self-storage unit rental application with size, duration, and access requirements",
          category: "moving",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Tenant Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "full", label: "Home / Billing Address" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Unit Details" }],
            [{ type: :select, width: "half", label: "Unit Size (5x5, 5x10, 10x10, 10x20, 10x30)" }, { type: :select, width: "half", label: "Storage Type (Indoor, Outdoor, Drive-Up)" }],
            [{ type: :date, width: "half", label: "Desired Move-in Date" }, { type: :select, width: "half", label: "Rental Duration (Monthly, 3 Months, 6 Months, Annual)" }],
            [{ type: :select, width: "half", label: "Access Hours (Standard, 24/7, Extended)" }, { type: :select, width: "half", label: "Floor Preference (Ground, Upper, No Preference)" }],
            [{ type: :radio, width: "full", label: "Climate Control Required?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Storage Requirements" }],
            [{ type: :checkbox, width: "full", label: "Items Being Stored (Furniture, Electronics, Vehicles, Documents, Clothing, Appliances, Business Inventory, Other)" }],
            [{ type: :radio, width: "full", label: "Any hazardous or oversized items?" }],
            [{ type: :radio, width: "full", label: "Need moving supplies or truck rental?" }],
            [{ type: :select, width: "half", label: "Payment Method" }, { type: :radio, width: "half", label: "Auto-pay enrollment?" }],
            [{ type: :textarea, width: "full", label: "Special Requirements or Notes" }],
            [{ type: :checkbox, width: "full", label: "I agree to the rental terms, insurance requirements, and access policies" }]
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
              "textarea" => "full"
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Unit Details", match_types: %w[select date radio] },
              { label: "Requirements", match_types: %w[checkbox textarea] }
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
