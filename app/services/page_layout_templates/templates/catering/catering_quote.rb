# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Catering
      module CateringQuote
        DEFINITION = {
          key: "catering_quote_request",
          name: "Catering Quote Request",
          description: "Event catering quote with guest count, menu preferences, dietary needs, and venue details",
          category: "catering",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Contact & Event Info" }],
            [{ type: :input, width: "half", label: "Contact Name" }, { type: :input, width: "half", label: "Company / Organization" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :select, width: "half", label: "Event Type (Wedding, Corporate, Birthday, Holiday, Fundraiser, Other)" }, { type: :date, width: "half", label: "Event Date" }],
            [{ type: :select, width: "half", label: "Event Start Time" }, { type: :select, width: "half", label: "Event Duration (Hours)" }],
            [{ type: :number, width: "half", label: "Expected Number of Guests" }, { type: :radio, width: "half", label: "Is the guest count confirmed?" }],
            [{ type: :input, width: "full", label: "Venue Name & Address" }],
            [{ type: :radio, width: "full", label: "Is the venue indoor or outdoor?" }],
            [{ type: :radio, width: "full", label: "Does the venue have a kitchen / prep area available?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Event & Menu Details" }],
            [{ type: :select, width: "half", label: "Service Style (Buffet, Plated, Family-Style, Stations, Cocktail)" }, { type: :select, width: "half", label: "Cuisine Type / Theme" }],
            [{ type: :checkbox, width: "full", label: "Meal Courses (Appetizers, Salad, Soup, Main Entree, Side Dishes, Dessert, Beverages)" }],
            [{ type: :checkbox, width: "full", label: "Dietary Requirements (Vegetarian, Vegan, Gluten-Free, Dairy-Free, Nut Allergy, Kosher, Halal)" }],
            [{ type: :number, width: "half", label: "Number of Vegetarian Meals" }, { type: :number, width: "half", label: "Number of Vegan Meals" }],
            [{ type: :radio, width: "full", label: "Will you need beverage service?" }],
            [{ type: :checkbox, width: "full", label: "Beverages (Water, Soda, Juice, Coffee, Tea, Beer, Wine, Champagne, Full Bar, Cocktails)" }],
            [{ type: :select, width: "half", label: "Bar Service Type (Open Bar, Cash Bar, Limited)" }, { type: :radio, width: "half", label: "Will you provide your own alcohol (BYOB)?" }],
            [{ type: :checkbox, width: "full", label: "Equipment & Rentals (Tables, Chairs, Linens, China, Glassware, Flatware, Chafers, Tents, Lighting)" }],
            [{ type: :radio, width: "full", label: "Will the caterer need to provide staff (servers, bartenders, chefs)?" }],
            [{ type: :select, width: "half", label: "Budget Per Person Range" }, { type: :number, width: "half", label: "Total Event Budget ($)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Special Requests" }],
            [{ type: :textarea, width: "full", label: "Specific Menu Requests, Themes, or Special Notes" }],
            [{ type: :file, width: "full", label: "Upload Event Inspiration Photos or Floor Plan (optional)" }],
            [{ type: :date, width: "half", label: "Quote Needed By" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }]
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
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact & Event Info", match_types: %w[text email tel] },
              { label: "Event & Menu Details", match_types: %w[number select date checkbox radio] },
              { label: "Special Requests", match_types: %w[textarea file] }
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
