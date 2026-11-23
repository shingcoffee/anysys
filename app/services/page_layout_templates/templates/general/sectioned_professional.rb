# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module SectionedProfessional
        DEFINITION = {
          key: "sectioned_professional",
          name: "Professional Sectioned",
          description: "Fields organized by type with clear section headings and dividers",
          category: "general",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Text Fields" }],
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :divider }],
            [{ type: :section, label: "Options" }],
            [{ type: :select, width: "half" }, { type: :select, width: "half" }],
            [{ type: :divider }],
            [{ type: :section, label: "Details" }],
            [{ type: :textarea, width: "full" }]
          ],
          layout: {
            default_width: "full",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "third",
              "date" => "third",
              "select" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "half",
              "url" => "half",
              "time" => "third",
              "datetime-local" => "half",
              "month" => "third",
              "week" => "third",
              "range" => "full",
              "color" => "third",
              "password" => "half",
              "search" => "half",
              "hidden" => "half",
            },
            sections: [
              { label: "Text Fields", match_types: %w[text email tel password search hidden url] },
              { label: "Selections", match_types: %w[select radio checkbox] },
              { label: "Numbers & Dates", match_types: %w[number date range time datetime-local month week] },
              { label: "Content & Media", match_types: %w[textarea file color] }
            ],
            inject_elements: [
              { after_section: 0, type: "divider" },
              { after_section: 1, type: "divider" },
              { after_section: 2, type: "divider" }
            ]
          }
        }.freeze
      end
    end
  end
end
