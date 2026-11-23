# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hospitality
      module RestaurantFeedback
        DEFINITION = {
          key: "restaurant_feedback",
          name: "Restaurant Feedback",
          description: "Dining experience survey with food, service, and ambiance ratings",
          category: "hospitality",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Visit Details" }],
            [{ type: :date, width: "half", label: "Visit Date" }, { type: :select, width: "half", label: "Meal Type (Breakfast, Brunch, Lunch, Dinner, Happy Hour, Late Night)" }],
            [{ type: :select, width: "half", label: "Party Size" }, { type: :select, width: "half", label: "Dining Method (Dine-In, Takeout, Delivery, Curbside)" }],
            [{ type: :input, width: "half", label: "Server / Staff Name (optional)" }, { type: :select, width: "half", label: "Reservation or Walk-In?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Ratings" }],
            [{ type: :select, width: "half", label: "Overall Experience (1-Poor to 5-Excellent)" }, { type: :select, width: "half", label: "Food Quality (1-5)" }],
            [{ type: :select, width: "half", label: "Service / Staff (1-5)" }, { type: :select, width: "half", label: "Ambiance / Atmosphere (1-5)" }],
            [{ type: :select, width: "half", label: "Value for Money (1-5)" }, { type: :select, width: "half", label: "Cleanliness (1-5)" }],
            [{ type: :radio, width: "full", label: "Would you return to this restaurant?" }],
            [{ type: :radio, width: "full", label: "Would you recommend us to friends or family?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Comments & Contact" }],
            [{ type: :textarea, width: "full", label: "What did you enjoy most?" }],
            [{ type: :textarea, width: "full", label: "What could we improve?" }],
            [{ type: :input, width: "half", label: "Name (optional)" }, { type: :input, width: "half", label: "Email (optional)" }],
            [{ type: :checkbox, width: "full", label: "I'd like to receive offers and updates from this restaurant" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "range" => "full",
            },
            sections: [
              { label: "Visit Details", match_types: %w[date select] },
              { label: "Your Ratings", match_types: %w[radio range] },
              { label: "Comments & Contact", match_types: %w[textarea text email checkbox] }
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
