# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module Blank
        DEFINITION = {
          key: "blank",
          name: "Blank Canvas",
          description: "Start from scratch — no layout modifications applied",
          category: "general",
          theme_preset: "modern",
          # Layout-only template: no labels, so it seeds no attributes — it only
          # arranges whatever attributes the entity already has.
          preview_rows: [
            [{ type: :input, width: "full" }],
            [{ type: :input, width: "full" }],
            [{ type: :input, width: "full" }],
            [{ type: :textarea, width: "full" }]
          ],
          layout: {
            default_width: "full",
            field_width_rules: {},
            sections: [],
            inject_elements: []
          }
        }.freeze
      end
    end
  end
end
