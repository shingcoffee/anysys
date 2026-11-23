# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Catering
      module MenuSelection
        DEFINITION = {
          key: "catering_menu_selection",
          name: "Catering Menu Selection",
          description: "Pre-event menu selection form for confirmed catering orders with course choices and dietary notes",
          category: "catering",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Guest Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Event Name / Booking Reference" }],
            [{ type: :input, width: "half", label: "Table Number / Seat Assignment" }, { type: :number, width: "half", label: "Number of Guests at Table" }],
            [{ type: :divider }],
            [{ type: :section, label: "Course Selections" }],
            [{ type: :select, width: "half", label: "Appetizer / Starter Course" }, { type: :select, width: "half", label: "Soup or Salad" }],
            [{ type: :select, width: "full", label: "Main Course / Entree" }],
            [{ type: :select, width: "half", label: "Side Dish #1" }, { type: :select, width: "half", label: "Side Dish #2" }],
            [{ type: :select, width: "half", label: "Dessert Selection" }, { type: :select, width: "half", label: "Beverage Preference" }],
            [{ type: :number, width: "half", label: "Number of Children's Meals" }, { type: :select, width: "half", label: "Children's Meal Option" }],
            [{ type: :divider }],
            [{ type: :section, label: "Dietary Restrictions & Notes" }],
            [{ type: :checkbox, width: "full", label: "Dietary Requirements (Vegetarian, Vegan, Gluten-Free, Dairy-Free, Nut Allergy, Shellfish Allergy, Soy Allergy, Kosher, Halal, Low-Sodium, Diabetic-Friendly)" }],
            [{ type: :textarea, width: "full", label: "Additional Dietary Requirements or Allergy Details" }],
            [{ type: :radio, width: "full", label: "Do you require alcohol-free beverages only?" }],
            [{ type: :textarea, width: "full", label: "Special Requests or Preparation Notes" }],
            [{ type: :date, width: "half", label: "Menu Selection Deadline" }, { type: :select, width: "half", label: "How did you hear about this event?" }],
            [{ type: :checkbox, width: "full", label: "I confirm my attendance and understand menu selections are final after the deadline" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Guest Information", match_types: %w[text email tel] },
              { label: "Course Selections", match_types: %w[select number] },
              { label: "Dietary Restrictions & Notes", match_types: %w[checkbox radio textarea date] }
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
