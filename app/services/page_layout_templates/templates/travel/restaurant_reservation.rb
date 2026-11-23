# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Travel
      module RestaurantReservation
        DEFINITION = {
          key: "restaurant_reservation",
          name: "Restaurant Reservation",
          description: "Table booking with party size, date/time, and dietary preferences",
          category: "travel",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Guest Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Reservation Details" }],
            [{ type: :date, width: "half", label: "Preferred Date" }, { type: :select, width: "half", label: "Preferred Time" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time" }],
            [{ type: :number, width: "half", label: "Number of Adults" }, { type: :number, width: "half", label: "Number of Children" }],
            [{ type: :select, width: "half", label: "Seating Preference (Indoor, Outdoor, Bar, Private Room)" }, { type: :select, width: "half", label: "Occasion (Birthday, Anniversary, Business, Date Night, General)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Dietary & Notes" }],
            [{ type: :checkbox, width: "full", label: "Dietary Preferences / Restrictions (Vegetarian, Vegan, Gluten-Free, Nut Allergy, Halal, Kosher)" }],
            [{ type: :radio, width: "full", label: "Would you like a custom menu / chef's special?" }],
            [{ type: :textarea, width: "full", label: "Special Occasion Details or Additional Notes" }],
            [{ type: :checkbox, width: "full", label: "I understand reservations held for 15 minutes past booking time" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Guest Details", match_types: %w[text email tel url] },
              { label: "Reservation Details", match_types: %w[date select number radio time] },
              { label: "Preferences & Notes", match_types: %w[checkbox textarea] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
