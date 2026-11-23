# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Religious
      module ChurchEvent
        DEFINITION = {
          key: "church_event",
          name: "Church Event Registration",
          description: "Faith community event signup with group size and dietary needs",
          category: "religious",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :select, width: "half", label: "Ministry / Group" }],
            [{ type: :input, width: "half", label: "Member ID (if applicable)" }, { type: :select, width: "half", label: "Member Status (Member, Regular Visitor, Guest)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Event Details" }],
            [{ type: :select, width: "half", label: "Event Name" }, { type: :date, width: "half", label: "Event Date" }],
            [{ type: :number, width: "half", label: "Adults Attending" }, { type: :number, width: "half", label: "Children Attending" }],
            [{ type: :number, width: "half", label: "Children Ages (list)" }, { type: :select, width: "half", label: "T-Shirt Size (if applicable)" }],
            [{ type: :radio, width: "full", label: "Need Transportation?" }],
            [{ type: :input, width: "full", label: "Pickup Address (if transportation needed)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Preferences & Accessibility" }],
            [{ type: :checkbox, width: "full", label: "Dietary Restrictions (Vegetarian, Vegan, Gluten-Free, Halal, Kosher, Nut Allergy, Other)" }],
            [{ type: :radio, width: "full", label: "Do you require accessibility accommodations?" }],
            [{ type: :textarea, width: "full", label: "Special Requests or Notes" }],
            [{ type: :checkbox, width: "full", label: "I consent to photos/videos being taken at this event for church use" }]
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
              "textarea" => "full"
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Event Details", match_types: %w[select number date radio] },
              { label: "Preferences & Notes", match_types: %w[textarea checkbox] }
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
