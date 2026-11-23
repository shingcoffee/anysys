# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module Default
        DEFINITION = {
          key: "default",
          name: "Default",
          description: "Auto-arranged layout — groups by your curated attribute groups (falls back to source-based sections when none are defined), and picks sensible widths for every field type.",
          category: "general",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Primary Information" }],
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :input, width: "half" }, { type: :select, width: "half" }],
            [{ type: :divider }],
            [{ type: :section, label: "Linked: Address" }],
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :divider }],
            [{ type: :section, label: "Additional Details" }],
            [{ type: :textarea, width: "full" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "textarea" => "full",
              "search" => "half",
              "password" => "half",
              "hidden" => "half",
              "select" => "half",
              "multi-select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "switch" => "full",
              "number" => "half",
              "currency" => "half",
              "range" => "third",
              "rating" => "third",
              "date" => "half",
              "time" => "half",
              "datetime-local" => "half",
              "month" => "third",
              "week" => "third",
              "email" => "half",
              "tel" => "half",
              "url" => "half",
              "rich-text" => "full",
              "signature" => "full",
              "file" => "full",
              "image" => "full",
              "color" => "third"
            },
            group_by: :attribute_groups,
            sections: [],
            inject_elements: []
          }
        }.freeze
      end
    end
  end
end
