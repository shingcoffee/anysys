# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hospitality
      module RoomServiceOrder
        DEFINITION = {
          key: "room_service_order",
          name: "Room Service Order",
          description: "Hotel room service menu order with delivery time and special requests",
          category: "hospitality",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Guest Info" }],
            [{ type: :input, width: "half", label: "Guest Name" }, { type: :input, width: "half", label: "Room Number" }],
            [{ type: :input, width: "half", label: "Phone Extension" }, { type: :number, width: "half", label: "Number of Guests Dining" }],
            [{ type: :divider }],
            [{ type: :section, label: "Menu Selections" }],
            [{ type: :checkbox, width: "full", label: "Appetizers (Soup, Salad, Shrimp Cocktail, Cheese Plate, Bruschetta, Wings)" }],
            [{ type: :checkbox, width: "full", label: "Main Courses (Club Sandwich, Burger, Pasta, Grilled Chicken, Steak, Vegetarian Option, Fish)" }],
            [{ type: :checkbox, width: "full", label: "Sides (Fries, Steamed Vegetables, Rice, Mashed Potatoes, Mixed Green Salad, Garlic Bread)" }],
            [{ type: :checkbox, width: "full", label: "Desserts (Chocolate Cake, Cheesecake, Ice Cream, Fresh Fruit, Crème Brûlée)" }],
            [{ type: :checkbox, width: "full", label: "Beverages (Coffee, Tea, Orange Juice, Soft Drink, Sparkling Water, Still Water, Beer, Wine, Cocktail)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Delivery & Notes" }],
            [{ type: :select, width: "half", label: "Preferred Delivery Time" }, { type: :select, width: "half", label: "Table Setup (Standard, Romantic, Business)" }],
            [{ type: :radio, width: "full", label: "Leave order at door (contactless delivery)?" }],
            [{ type: :textarea, width: "full", label: "Dietary Requirements, Allergies, or Special Requests" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Guest Info", match_types: %w[text tel number] },
              { label: "Menu Selections", match_types: %w[checkbox] },
              { label: "Delivery & Notes", match_types: %w[select radio textarea time] }
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
