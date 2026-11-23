# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Food
      module RestaurantOrder
        DEFINITION = {
          key: "restaurant_order",
          name: "Restaurant Order",
          description: "Online food ordering with menu categories, customizations, and delivery details",
          category: "food",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Customer Details" }],
            [{ type: :input, width: "half", label: "Name" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :input, width: "half", label: "Email" }, { type: :select, width: "half", label: "Order Type (Delivery, Pickup, Dine-In)" }],
            [{ type: :input, width: "full", label: "Delivery Address (if delivery)" }],
            [{ type: :date, width: "half", label: "Date" }, { type: :select, width: "half", label: "Scheduled Time" }],
            [{ type: :divider }],
            [{ type: :section, label: "Order Items" }],
            [{ type: :select, width: "half", label: "Item 1 - Category" }, { type: :select, width: "half", label: "Item 1 - Menu Item" }],
            [{ type: :number, width: "half", label: "Qty 1" }, { type: :select, width: "half", label: "Size / Variant 1" }],
            [{ type: :select, width: "half", label: "Item 2 - Category" }, { type: :select, width: "half", label: "Item 2 - Menu Item" }],
            [{ type: :number, width: "half", label: "Qty 2" }, { type: :select, width: "half", label: "Size / Variant 2" }],
            [{ type: :checkbox, width: "full", label: "Add-ons: Extra Sauce, Extra Cheese, Bacon, Avocado, Jalapeños, No Onion, Gluten-Free Option" }],
            [{ type: :textarea, width: "full", label: "Special Instructions / Allergies" }],
            [{ type: :divider }],
            [{ type: :section, label: "Payment" }],
            [{ type: :select, width: "half", label: "Payment Method (Card, Cash, Apple Pay, Other)" }, { type: :input, width: "half", label: "Promo Code" }],
            [{ type: :radio, width: "full", label: "Include contactless delivery?" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "number" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Customer Info", match_types: %w[text email tel select date] },
              { label: "Order Details", match_types: %w[number checkbox textarea] },
              { label: "Payment", match_types: %w[radio] }
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
