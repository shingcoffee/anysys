# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Social
      module ReunionRegistration
        DEFINITION = {
          key: "reunion_registration",
          name: "Reunion Registration",
          description: "Family or class reunion signup with activities and accommodation",
          category: "social",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "City / State" }],
            [{ type: :input, width: "half", label: "Graduating Year / Family Branch" }, { type: :select, width: "half", label: "How Did You Hear About the Reunion?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Attendance Details" }],
            [{ type: :number, width: "half", label: "Adults Attending" }, { type: :number, width: "half", label: "Children Attending" }],
            [{ type: :select, width: "half", label: "Meal Preference" }, { type: :select, width: "half", label: "T-Shirt Size" }],
            [{ type: :checkbox, width: "full", label: "Dietary Restrictions (Vegetarian, Vegan, Gluten-Free, Nut Allergy, Other)" }],
            [{ type: :checkbox, width: "full", label: "Activities Interested In (BBQ, Tours, Games, Photo Session, Group Dinner, Sports)" }],
            [{ type: :radio, width: "full", label: "Need Accommodation Assistance?" }],
            [{ type: :select, width: "half", label: "Preferred Accommodation Type (Hotel, Campsite, Host Family)" }, { type: :date, width: "half", label: "Arrival Date" }],
            [{ type: :date, width: "half", label: "Departure Date" }, { type: :select, width: "half", label: "Payment Method" }],
            [{ type: :divider }],
            [{ type: :section, label: "Notes & Updates" }],
            [{ type: :textarea, width: "full", label: "Life Updates (optional — share what you've been up to)" }],
            [{ type: :textarea, width: "full", label: "Special Requests or Accessibility Needs" }],
            [{ type: :checkbox, width: "full", label: "I consent to photos being taken and shared in reunion album" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Attendance Details", match_types: %w[number select date radio checkbox] },
              { label: "Additional Info", match_types: %w[textarea] }
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
