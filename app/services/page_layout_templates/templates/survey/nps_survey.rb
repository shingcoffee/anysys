# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Survey
      module NpsSurvey
        DEFINITION = {
          key: "nps_survey",
          name: "NPS Survey",
          description: "Net Promoter Score survey — rating scale with follow-up",
          category: "survey",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Your Rating" }],
            [{ type: :select, width: "full", label: "How likely are you to recommend us to a friend or colleague? (0 = Not at all, 10 = Extremely likely)" }],
            [{ type: :select, width: "half", label: "Product / Service Experience" }, { type: :select, width: "half", label: "Customer Support Experience" }],
            [{ type: :divider }],
            [{ type: :section, label: "Follow-up Questions" }],
            [{ type: :radio, width: "full", label: "What best describes the main reason for your score?" }],
            [{ type: :radio, width: "full", label: "How long have you been a customer?" }],
            [{ type: :select, width: "half", label: "Which product / service did you use most recently?" }, { type: :select, width: "half", label: "How did you interact with us? (Online, Phone, In-Person, App)" }],
            [{ type: :textarea, width: "full", label: "What do we do well?" }],
            [{ type: :textarea, width: "full", label: "What could we do better?" }],
            [{ type: :textarea, width: "full", label: "Any other comments?" }],
            [{ type: :input, width: "half", label: "Name (optional)" }, { type: :input, width: "half", label: "Email (optional — for follow-up)" }],
            [{ type: :checkbox, width: "full", label: "I am open to being contacted for a more detailed conversation" }]
          ],
          layout: {
            default_width: "full",
            field_width_rules: {
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "text" => "half",
              "email" => "half",
              "checkbox" => "full",
              "range" => "full",
            },
            sections: [
              { label: "Score", match_types: %w[select range] },
              { label: "Follow-up", match_types: %w[radio textarea] },
              { label: "Contact", match_types: %w[text email checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
