# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Nonprofit
      module PetitionForm
        DEFINITION = {
          key: "petition_form",
          name: "Petition / Pledge",
          description: "Collect supporter signatures for a cause or campaign pledge",
          category: "nonprofit",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Sign the Petition" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "full", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone (Optional)" }, { type: :input, width: "half", label: "City" }],
            [{ type: :input, width: "half", label: "State / Province" }, { type: :input, width: "half", label: "ZIP / Postal Code" }],
            [{ type: :select, width: "half", label: "Country" }, { type: :select, width: "half", label: "Age Group" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Voice" }],
            [{ type: :textarea, width: "full", label: "Why this cause matters to you" }],
            [{ type: :radio, width: "full", label: "How did you hear about this petition?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Options & Consent" }],
            [{ type: :checkbox, width: "full", label: "Display my name publicly on the petition" }],
            [{ type: :checkbox, width: "full", label: "Keep me updated on the progress of this campaign" }],
            [{ type: :checkbox, width: "full", label: "I am a real person and support this petition" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "full",
              "tel" => "half",
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Your Information", match_types: %w[text email tel select url] },
              { label: "Your Voice", match_types: %w[textarea radio] },
              { label: "Options & Consent", match_types: %w[checkbox] }
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
