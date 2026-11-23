# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Interiordesign
      module StyleQuiz
        DEFINITION = {
          key: "interior_style_quiz",
          name: "Interior Design Style Quiz",
          description: "Design style preference quiz with room photos, color palette choices, and lifestyle questions",
          category: "interiordesign",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "About You" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :select, width: "half", label: "City / Location" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Style Preferences" }],
            [{ type: :radio, width: "full", label: "Which interior style appeals to you most? (Modern, Traditional, Bohemian, Scandinavian, Industrial, Mid-century, Coastal, Eclectic)" }],
            [{ type: :radio, width: "full", label: "Preferred color palette? (Neutral/White, Warm Earth, Cool Blues/Greens, Bold Colors, Monochrome, Mixed)" }],
            [{ type: :radio, width: "full", label: "Furniture style preference? (Clean Lines, Rustic, Ornate, Minimalist, Mixed)" }],
            [{ type: :select, width: "half", label: "Lighting Preference (Natural, Warm/Dim, Bright/White, Layered)" }, { type: :select, width: "half", label: "Texture Preference (Smooth, Cozy/Textured, Mixed)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Space & Project" }],
            [{ type: :select, width: "half", label: "Room Type (Living Room, Bedroom, Kitchen, Bathroom, Office, Whole Home)" }, { type: :select, width: "half", label: "Room Size (Small, Medium, Large, Open Plan)" }],
            [{ type: :select, width: "half", label: "Budget Range" }, { type: :select, width: "half", label: "Timeline" }],
            [{ type: :checkbox, width: "full", label: "Design Priorities (Functionality, Aesthetics, Storage, Comfort, Entertaining, Kids/Pet Friendly, Eco-Friendly)" }],
            [{ type: :radio, width: "full", label: "Do you have pets?" }],
            [{ type: :radio, width: "full", label: "Do you have children?" }],
            [{ type: :textarea, width: "full", label: "Describe your dream space" }],
            [{ type: :file, width: "full", label: "Upload Inspiration Images (optional)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact", match_types: %w[text email tel] },
              { label: "Style & Space", match_types: %w[radio select checkbox] },
              { label: "Vision & Inspiration", match_types: %w[textarea file] }
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
