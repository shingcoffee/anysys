# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module SettingsPreferences
        DEFINITION = {
          key: "settings_preferences",
          name: "Settings Panel",
          description: "Toggle-heavy preferences screen for configuration forms",
          category: "general",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "General" }],
            [{ type: :checkbox, width: "full", label: "Enable notifications" }],
            [{ type: :checkbox, width: "full", label: "Dark mode" }],
            [{ type: :checkbox, width: "full", label: "Auto-save" }],
            [{ type: :divider }],
            [{ type: :section, label: "Privacy" }],
            [
              { type: :select, width: "half", label: "Visibility" },
              { type: :select, width: "half", label: "Language" }
            ],
            [{ type: :checkbox, width: "full", label: "Analytics opt-in" }]
          ],
          layout: {
            default_width: "full",
            field_width_rules: {
              "checkbox" => "full",
              "radio" => "full",
              "select" => "half",
              "text" => "half",
              "number" => "half",
              "email" => "half",
              "tel" => "half",
              "range" => "full",
            },
            sections: [
              { label: "General Settings", match_types: %w[checkbox] },
              { label: "Options", match_types: %w[radio select range] },
              { label: "Custom Values", match_types: %w[text number email tel url] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
