# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module ThreeColumnGrid
        DEFINITION = {
          key: "three_column_grid",
          name: "Three-Column Grid",
          description: "Dense grid layout — ideal for data-heavy forms",
          category: "general",
          theme_preset: "minimalist",
          # Layout-only template: no labels, so it seeds no attributes — it only
          # arranges whatever attributes the entity already has.
          preview_rows: [
            [{ type: :input, width: "third" }, { type: :input, width: "third" }, { type: :input, width: "third" }],
            [{ type: :input, width: "third" }, { type: :select, width: "third" }, { type: :number, width: "third" }],
            [{ type: :input, width: "third" }, { type: :input, width: "third" }, { type: :input, width: "third" }],
            [{ type: :textarea, width: "full" }]
          ],
          layout: {
            default_width: "third",
            field_width_rules: {
              "textarea" => "full",
              "radio" => "full",
              "checkbox" => "full",
              "file" => "full",
            },
            sections: [],
            inject_elements: []
          }
        }.freeze
      end
    end
  end
end
