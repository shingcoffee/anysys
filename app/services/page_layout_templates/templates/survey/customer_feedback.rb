# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Survey
      module CustomerFeedback
        DEFINITION = {
          key: "customer_feedback",
          name: "Customer Feedback",
          description: "Star ratings, satisfaction scales, and open comments",
          category: "survey",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "About Your Experience" }],
            [{ type: :input, width: "half", label: "Your Name (optional)" }, { type: :input, width: "half", label: "Email (optional)" }],
            [{ type: :input, width: "half", label: "Order / Reference Number (if applicable)" }, { type: :date, width: "half", label: "Date of Experience" }],
            [{ type: :select, width: "half", label: "Product / Service Used" }, { type: :select, width: "half", label: "Channel (In-Store, Online, Phone, App)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Ratings" }],
            [{ type: :select, width: "half", label: "Overall Satisfaction (1-5)" }, { type: :select, width: "half", label: "Product / Service Quality" }],
            [{ type: :select, width: "half", label: "Ease of Use / Process" }, { type: :select, width: "half", label: "Customer Support (if contacted)" }],
            [{ type: :select, width: "half", label: "Value for Money" }, { type: :select, width: "half", label: "Likelihood to Recommend (1-10)" }],
            [{ type: :radio, width: "full", label: "Compared to other providers, how do we rate? (Better, About the Same, Worse)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Thoughts" }],
            [{ type: :textarea, width: "full", label: "What did you like most?" }],
            [{ type: :textarea, width: "full", label: "What could we improve?" }],
            [{ type: :textarea, width: "full", label: "Any additional comments or suggestions?" }],
            [{ type: :checkbox, width: "full", label: "I consent to my feedback being used for improvement and marketing purposes" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "range" => "full",
            },
            sections: [
              { label: "Experience Info", match_types: %w[text email date select] },
              { label: "Ratings", match_types: %w[radio] },
              { label: "Your Thoughts", match_types: %w[textarea checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
