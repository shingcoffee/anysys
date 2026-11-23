# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module DataEntryAdmin
        DEFINITION = {
          key: "data_entry_admin",
          name: "Data Entry / Admin",
          description: "Compact admin panel with dense field arrangement",
          category: "general",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :input, width: "third" }, { type: :input, width: "third" }, { type: :select, width: "third" }],
            [{ type: :input, width: "half" }, { type: :number, width: "half" }],
            [{ type: :divider }],
            [
              { type: :checkbox, width: "third" },
              { type: :checkbox, width: "third" },
              { type: :checkbox, width: "third" }
            ],
            [{ type: :textarea, width: "full" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "number" => "third",
              "select" => "half",
              "checkbox" => "third",
              "textarea" => "full"
            },
            sections: [
              { label: "Core Fields", match_types: %w[text number] },
              { label: "Selections & Toggles", match_types: %w[select checkbox radio] },
              { label: "Extended Content", match_types: %w[textarea file] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
