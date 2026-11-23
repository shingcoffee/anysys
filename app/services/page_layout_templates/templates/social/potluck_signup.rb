# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Social
      module PotluckSignup
        DEFINITION = {
          key: "potluck_signup",
          name: "Potluck Signup",
          description: "Coordinate potluck dishes, servings, and arrival times",
          category: "social",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Your Information" }],
            [{ type: :input, width: "half", label: "Your Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :select, width: "half", label: "Arrival Time" }],
            [{ type: :divider }],
            [{ type: :section, label: "Dish Details" }],
            [{ type: :select, width: "half", label: "Dish Category (Appetizer, Main Course, Side Dish, Salad, Dessert, Beverage, Bread)" }, { type: :input, width: "half", label: "Dish Name" }],
            [{ type: :number, width: "half", label: "Servings Provided" }, { type: :select, width: "half", label: "Serving Temperature (Hot, Cold, Room Temp)" }],
            [{ type: :radio, width: "full", label: "Is this dish homemade or store-bought?" }],
            [{ type: :checkbox, width: "full", label: "Contains Allergens (Nuts, Dairy, Gluten, Eggs, Shellfish, Soy)" }],
            [{ type: :textarea, width: "full", label: "Ingredients / Preparation Notes" }],
            [{ type: :divider }],
            [{ type: :section, label: "Logistics" }],
            [{ type: :checkbox, width: "full", label: "Setup needs (Table Space, Electrical Outlet, Warming Station, Ice/Cooler)" }],
            [{ type: :radio, width: "full", label: "Bringing serving utensils?" }],
            [{ type: :textarea, width: "full", label: "Additional Notes for Organizer" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Your Info", match_types: %w[text email tel] },
              { label: "Dish Details", match_types: %w[select number radio checkbox] },
              { label: "Notes", match_types: %w[textarea] }
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
