# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module WizardMultiStep
        DEFINITION = {
          key: "wizard_multi_step",
          name: "Multi-Step Wizard",
          description: "Split fields across pages for a guided step-by-step flow",
          category: "general",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Step 1 — Basic Info" }],
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :select, width: "half" }, { type: :date, width: "half" }],
            [{ type: :divider }],
            [{ type: :section, label: "Step 2 — Details" }],
            [{ type: :textarea, width: "full" }],
            [{ type: :checkbox, width: "full" }]
          ],
          layout: {
            multi_page: true,
            pages_count: 3,
            default_width: "full",
            field_width_rules: {
              "text" => "half",
              "number" => "half",
              "select" => "half",
              "date" => "half",
              "email" => "half",
              "tel" => "half",
              "textarea" => "full",
              "checkbox" => "full",
              "time" => "half",
            },
            sections: [],
            inject_elements: []
          }
        }.freeze
      end
    end
  end
end
