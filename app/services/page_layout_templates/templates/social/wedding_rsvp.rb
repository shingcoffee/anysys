# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Social
      module WeddingRsvp
        DEFINITION = {
          key: "wedding_rsvp",
          name: "Wedding RSVP",
          description: "Elegant wedding response card with meal choices and plus-one details",
          category: "social",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Guest Information" }],
            [{ type: :input, width: "half", label: "Guest Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Table / Seating Assignment (if provided)" }],
            [{ type: :radio, width: "full", label: "Joyfully Accept / Regretfully Decline" }],
            [{ type: :divider }],
            [{ type: :section, label: "Attendance Details" }],
            [{ type: :number, width: "half", label: "Number of Adults Attending" }, { type: :number, width: "half", label: "Number of Children Attending" }],
            [{ type: :input, width: "half", label: "Plus-One Name (if applicable)" }, { type: :select, width: "half", label: "Plus-One Meal Choice" }],
            [{ type: :select, width: "half", label: "Ceremony Attendance (Ceremony + Reception, Reception Only)" }, { type: :select, width: "half", label: "Entree Selection" }],
            [{ type: :select, width: "half", label: "Plus-One Entree Selection" }, { type: :select, width: "half", label: "Children's Meal (if applicable)" }],
            [{ type: :checkbox, width: "full", label: "Dietary Restrictions (Vegetarian, Vegan, Gluten-Free, Nut Allergy, Kosher, Halal)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Special Details" }],
            [{ type: :radio, width: "full", label: "Will you require transportation assistance?" }],
            [{ type: :radio, width: "full", label: "Will you require accommodation?" }],
            [{ type: :textarea, width: "full", label: "Well Wishes for the Couple" }],
            [{ type: :input, width: "full", label: "Song Request for the Reception" }]
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
              { label: "Guest Details", match_types: %w[text email tel number] },
              { label: "Event Choices", match_types: %w[radio select checkbox] },
              { label: "Message", match_types: %w[textarea] }
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
