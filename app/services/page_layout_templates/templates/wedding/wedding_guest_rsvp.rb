# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Wedding
      module WeddingGuestRsvp
        DEFINITION = {
          key: "wedding_guest_rsvp",
          name: "Wedding Guest RSVP",
          description: "Elegant guest RSVP with meal selection, plus-one details, song requests, and dietary needs",
          category: "wedding",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Guest Info" }],
            [{ type: :input, width: "half", label: "Guest Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number (optional)" }, { type: :input, width: "half", label: "Mailing Address (if sending thank-you cards)" }],
            [{ type: :radio, width: "full", label: "Will you be attending?" }],
            [{ type: :number, width: "half", label: "Number of Guests in Your Party" }, { type: :input, width: "half", label: "Plus-One / Guest Name" }],
            [{ type: :divider }],
            [{ type: :section, label: "Meal & Dietary" }],
            [{ type: :select, width: "half", label: "Your Entrée Selection (Chicken, Beef, Fish, Vegetarian)" }, { type: :select, width: "half", label: "Plus-One Entrée Selection (if applicable)" }],
            [{ type: :checkbox, width: "full", label: "Dietary Restrictions (Vegetarian, Vegan, Gluten-Free, Dairy-Free, Nut Allergy, Kosher, Halal, Other)" }],
            [{ type: :textarea, width: "full", label: "Allergy Details or Special Meal Requests" }],
            [{ type: :divider }],
            [{ type: :section, label: "Extras" }],
            [{ type: :input, width: "full", label: "Song Request for the Dance Floor" }],
            [{ type: :radio, width: "full", label: "Will you need transportation assistance to / from the venue?" }],
            [{ type: :radio, width: "full", label: "Will you need accommodation (hotel block available)?" }],
            [{ type: :textarea, width: "full", label: "Message to the Couple" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Guest Info", match_types: %w[text email number] },
              { label: "Meal & Dietary", match_types: %w[select radio checkbox] },
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
