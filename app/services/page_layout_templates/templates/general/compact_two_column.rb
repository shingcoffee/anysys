# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module CompactTwoColumn
        DEFINITION = {
          key: "compact_two_column",
          name: "Two-Column Compact",
          description: "Side-by-side fields for efficient use of space",
          category: "general",
          theme_preset: "minimalist",
          # Layout-only template: no labels, so it seeds no attributes — it only
          # arranges whatever attributes the entity already has.
          preview_rows: [
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :input, width: "half" }, { type: :select, width: "half" }],
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :textarea, width: "full" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "textarea" => "full",
              "file" => "full",
              "radio" => "full",
              "checkbox" => "full"
            },
            sections: [],
            inject_elements: []
          }
        }.freeze
      end
    end
  end
end
