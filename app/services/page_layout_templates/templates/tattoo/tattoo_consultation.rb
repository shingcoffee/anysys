# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Tattoo
      module TattooConsultation
        DEFINITION = {
          key: "tattoo_consultation",
          name: "Tattoo Consultation Request",
          description: "Tattoo design consultation with style preferences, placement, size, and reference images",
          category: "tattoo",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Your Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Instagram Handle (optional)" }, { type: :select, width: "half", label: "How Did You Find Us?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Design Details" }],
            [{ type: :select, width: "half", label: "Tattoo Style (Traditional, Neo-Traditional, Realism, Watercolor, Geometric, Blackwork, Japanese, Fine Line, Other)" }, { type: :select, width: "half", label: "Body Placement" }],
            [{ type: :select, width: "half", label: "Approximate Size (Tiny < 2\", Small 2-4\", Medium 4-8\", Large 8\"+, Sleeve)" }, { type: :radio, width: "half", label: "Color or Black & Grey?" }],
            [{ type: :select, width: "half", label: "Preferred Artist (if any)" }, { type: :select, width: "half", label: "Budget Range" }],
            [{ type: :radio, width: "full", label: "Is this your first tattoo?" }],
            [{ type: :radio, width: "full", label: "Is this a cover-up or addition to existing work?" }],
            [{ type: :textarea, width: "full", label: "Describe Your Tattoo Idea in Detail" }],
            [{ type: :file, width: "full", label: "Upload Reference Images (photos, sketches, inspiration)" }],
            [{ type: :divider }],
            [{ type: :section, label: "References & Notes" }],
            [{ type: :radio, width: "full", label: "Any known skin conditions, keloid scarring, or allergies to ink?" }],
            [{ type: :textarea, width: "full", label: "Describe Skin Concerns (if yes)" }],
            [{ type: :date, width: "half", label: "Preferred Consultation Date" }, { type: :select, width: "half", label: "Preferred Time Window" }],
            [{ type: :textarea, width: "full", label: "Additional Notes or Questions" }],
            [{ type: :checkbox, width: "full", label: "I confirm I am 18+ years of age and understand a deposit may be required to book" }]
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
              "textarea" => "full",
              "radio" => "full",
              "checkbox" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel date] },
              { label: "Design Details", match_types: %w[select radio] },
              { label: "References & Notes", match_types: %w[textarea file checkbox] }
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
