# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Feedback
      module WebsiteFeedback
        DEFINITION = {
          key: "website_feedback",
          name: "Website Feedback",
          description: "Visitor experience survey with ratings and usability questions",
          category: "feedback",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Ratings" }],
            [{ type: :select, width: "half", label: "Overall Experience (1-Poor to 5-Excellent)" }, { type: :select, width: "half", label: "Ease of Navigation (1-5)" }],
            [{ type: :select, width: "half", label: "Design & Appearance (1-5)" }, { type: :select, width: "half", label: "Page Load Speed (1-5)" }],
            [{ type: :select, width: "half", label: "Content Quality & Accuracy (1-5)" }, { type: :select, width: "half", label: "Mobile Experience (1-5)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Thoughts" }],
            [{ type: :select, width: "full", label: "What brought you to our site today?" }],
            [{ type: :radio, width: "full", label: "Did you find what you were looking for?" }],
            [{ type: :radio, width: "full", label: "Would you return to this website?" }],
            [{ type: :radio, width: "full", label: "Would you recommend this site to others?" }],
            [{ type: :textarea, width: "full", label: "What can we improve?" }],
            [{ type: :textarea, width: "full", label: "What did you like most about the site?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Contact" }],
            [{ type: :input, width: "half", label: "Name (optional)" }, { type: :input, width: "half", label: "Email (optional)" }],
            [{ type: :checkbox, width: "full", label: "I'd like to be contacted about my feedback" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "range" => "full",
            },
            sections: [
              { label: "Ratings", match_types: %w[select range] },
              { label: "Your Thoughts", match_types: %w[radio textarea] },
              { label: "Contact", match_types: %w[text email checkbox] }
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
