# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hospitality
      module CateringOrder
        DEFINITION = {
          key: "catering_order",
          name: "Catering Order",
          description: "Event catering request with menu selection, headcount, and delivery",
          category: "hospitality",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Event Info" }],
            [{ type: :input, width: "half", label: "Event Name" }, { type: :select, width: "half", label: "Event Type (Corporate, Wedding, Birthday, Conference, Social, Other)" }],
            [{ type: :date, width: "half", label: "Event Date" }, { type: :select, width: "half", label: "Start Time" }],
            [{ type: :input, width: "full", label: "Venue Name & Address" }],
            [{ type: :number, width: "half", label: "Expected Guest Count" }, { type: :select, width: "half", label: "Service Style (Buffet, Plated, Family Style, Cocktail Stations)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Menu Selections" }],
            [{ type: :checkbox, width: "full", label: "Appetizers (Cheese Board, Bruschetta, Mini Sliders, Spring Rolls, Shrimp Cocktail)" }],
            [{ type: :checkbox, width: "full", label: "Entrees (Grilled Chicken, Beef Tenderloin, Salmon, Pasta Bar, Vegetarian Option)" }],
            [{ type: :checkbox, width: "full", label: "Sides & Salads (Caesar Salad, Roasted Vegetables, Rice Pilaf, Bread Rolls)" }],
            [{ type: :checkbox, width: "full", label: "Desserts (Wedding Cake, Fruit Tart, Cheesecake, Cookies, Mousse)" }],
            [{ type: :checkbox, width: "full", label: "Beverages (Coffee/Tea, Juice, Soft Drinks, Sparkling Water, Beer, Wine, Full Bar Service)" }],
            [{ type: :textarea, width: "full", label: "Dietary Restrictions, Allergies, or Special Menu Requests" }],
            [{ type: :select, width: "half", label: "Budget Range Per Person" }, { type: :select, width: "half", label: "Equipment Needed (Tables, Linens, Chairs, Chafers, None)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Contact & Logistics" }],
            [{ type: :input, width: "half", label: "Contact Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :textarea, width: "full", label: "Special Instructions or Additional Requests" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "number" => "half",
              "select" => "half",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Event Info", match_types: %w[text date number select] },
              { label: "Menu Selections", match_types: %w[checkbox textarea] },
              { label: "Contact & Logistics", match_types: %w[email tel] }
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
