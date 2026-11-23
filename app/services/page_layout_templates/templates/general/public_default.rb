# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module PublicDefault
        DEFINITION = {
          key: "public_default",
          name: "Default (Public)",
          description: "Public-facing layout — showcase theme, generous spacing, full-width fields that auto-collapse on mobile. Designed to look polished and trustworthy on first impression for anonymous internet users.",
          category: "general",
          theme_preset: "showcase",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "full" }],
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :divider }],
            [{ type: :section, label: "Details" }],
            [{ type: :select, width: "full" }],
            [{ type: :textarea, width: "full" }]
          ],
          layout: {
            audience: "public",
            default_width: "full",
            mobile_stack: true,
            field_width_rules: {
              "text" => "full", "search" => "full", "password" => "full", "hidden" => "full",
              "select" => "full", "multi-select" => "full",
              "radio" => "full", "checkbox" => "full", "switch" => "full",
              "number" => "half", "currency" => "half", "range" => "full", "rating" => "full",
              "date" => "half", "time" => "half", "datetime-local" => "full",
              "month" => "full", "week" => "full",
              "email" => "full", "tel" => "full", "url" => "full",
              "rich-text" => "full", "signature" => "full",
              "file" => "full", "image" => "full",
              "color" => "half", "textarea" => "full"
            },
            group_by: :attribute_groups,
            sections: [],
            inject_elements: [
              { after_section: 0, type: "spacer" },
              { after_section: 1, type: "divider" },
              { after_section: 2, type: "divider" },
              { after_section: 3, type: "spacer" }
            ]
          }.freeze
        }.freeze
      end
    end
  end
end
