# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Seniorcare
      module ActivitySignup
        DEFINITION = {
          key: "senior_activity_signup",
          name: "Senior Activity Signup",
          description: "Community center or assisted living activity registration with accessibility and dietary needs",
          category: "seniorcare",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Participant Information" }],
            [{ type: :input, width: "half", label: "Participant Full Name" }, { type: :input, width: "half", label: "Room / Unit Number" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Emergency Contact Name & Phone" }],
            [{ type: :select, width: "half", label: "Mobility Status (Independent, Walker, Wheelchair, Staff-Assisted)" }, { type: :select, width: "half", label: "Cognitive Level (Independent, Reminiscence, Memory Care)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Activities & Schedule" }],
            [{ type: :checkbox, width: "full", label: "Activities of Interest (Arts & Crafts, Music, Exercise, Bingo, Gardening, Movies, Cooking, Cards/Games, Religious Services, Outings, Technology)" }],
            [{ type: :select, width: "half", label: "Preferred Day(s) (Weekdays, Weekends, Any)" }, { type: :select, width: "half", label: "Preferred Time (Morning, Afternoon, Evening)" }],
            [{ type: :radio, width: "full", label: "Will the participant need mobility / transport assistance to attend?" }],
            [{ type: :radio, width: "full", label: "Does the participant need an aide or companion during activities?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Accommodations" }],
            [{ type: :checkbox, width: "full", label: "Dietary Restrictions (Vegetarian, Vegan, Gluten-Free, Diabetic, Low-Sodium, Soft Foods, Thickened Liquids, No Restrictions)" }],
            [{ type: :radio, width: "full", label: "Does the participant have any allergies (food or environmental)?" }],
            [{ type: :textarea, width: "full", label: "Describe Allergies or Sensitivities (if yes)" }],
            [{ type: :textarea, width: "full", label: "Special Accommodations or Notes for Activity Staff" }],
            [{ type: :checkbox, width: "full", label: "I consent to participation and acknowledge any associated risks have been discussed with the care team" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Participant Info", match_types: %w[text email tel] },
              { label: "Activities & Schedule", match_types: %w[checkbox select radio] },
              { label: "Accommodations", match_types: %w[textarea] }
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
