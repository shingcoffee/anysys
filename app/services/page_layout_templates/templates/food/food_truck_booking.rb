# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Food
      module FoodTruckBooking
        DEFINITION = {
          key: "food_truck_booking",
          name: "Food Truck Booking",
          description: "Book a food truck for events with menu preferences, guest count, and location details",
          category: "food",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Contact Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Organization / Company" }],
            [{ type: :divider }],
            [{ type: :section, label: "Event Details" }],
            [{ type: :select, width: "half", label: "Event Type (Corporate, Wedding, Festival, Birthday, School, Other)" }, { type: :number, width: "half", label: "Expected Number of Guests" }],
            [{ type: :date, width: "half", label: "Event Date" }, { type: :date, width: "half", label: "Alternate Date" }],
            [{ type: :select, width: "half", label: "Service Start Time" }, { type: :select, width: "half", label: "Service Duration (hrs)" }],
            [{ type: :input, width: "full", label: "Event Location / Address" }],
            [{ type: :radio, width: "full", label: "Is there electrical power available on-site?" }],
            [{ type: :radio, width: "full", label: "Is there a water hookup available?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Menu & Budget" }],
            [{ type: :checkbox, width: "full", label: "Cuisine Preferences (American, Mexican, Asian, Mediterranean, BBQ, Vegan, Fusion, Other)" }],
            [{ type: :checkbox, width: "full", label: "Dietary Accommodations Needed (Vegetarian, Vegan, Gluten-Free, Nut-Free, Halal)" }],
            [{ type: :select, width: "half", label: "Budget per Person ($)" }, { type: :select, width: "half", label: "Service Style (Self-Serve, Full Service, Pre-order, Custom)" }],
            [{ type: :textarea, width: "full", label: "Additional Details or Special Requests" }]
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
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Event Details", match_types: %w[select number date radio time] },
              { label: "Menu & Notes", match_types: %w[checkbox textarea] }
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
