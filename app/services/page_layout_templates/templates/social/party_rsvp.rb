# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Social
      module PartyRsvp
        DEFINITION = {
          key: "party_rsvp",
          name: "Party Invitation RSVP",
          description: "Event RSVP with guest count, dietary preferences, and song requests",
          category: "social",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Your Information" }],
            [{ type: :input, width: "half", label: "Your Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Who Invited You?" }],
            [{ type: :divider }],
            [{ type: :section, label: "RSVP Details" }],
            [{ type: :radio, width: "full", label: "Will You Attend?" }],
            [{ type: :number, width: "half", label: "Number of Adults Attending" }, { type: :number, width: "half", label: "Number of Children Attending" }],
            [{ type: :select, width: "half", label: "Meal Preference" }, { type: :select, width: "half", label: "Preferred Arrival Time" }],
            [{ type: :checkbox, width: "full", label: "Dietary Restrictions (Vegetarian, Vegan, Gluten-Free, Nut Allergy, None)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Fun Extras" }],
            [{ type: :input, width: "full", label: "Song Request for the Playlist" }],
            [{ type: :input, width: "half", label: "Bring a Dish? (describe)" }, { type: :select, width: "half", label: "Dish Category (Appetizer, Side, Main, Dessert, Drinks, None)" }],
            [{ type: :textarea, width: "full", label: "Message to the Host" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Guest Info", match_types: %w[text email tel] },
              { label: "RSVP Details", match_types: %w[radio select number checkbox] },
              { label: "Extras", match_types: %w[textarea] }
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
