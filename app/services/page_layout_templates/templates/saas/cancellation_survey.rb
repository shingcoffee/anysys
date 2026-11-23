# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Saas
      module CancellationSurvey
        DEFINITION = {
          key: "cancellation_survey",
          name: "Cancellation Survey",
          description: "Customer churn feedback with reason, satisfaction rating, and win-back offer",
          category: "saas",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Account Information" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Account ID / Username" }],
            [{ type: :select, width: "half", label: "Plan / Tier (Free, Starter, Pro, Enterprise)" }, { type: :select, width: "half", label: "How Long Were You a Customer?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Feedback" }],
            [{ type: :select, width: "full", label: "Primary Reason for Cancelling (Too Expensive, Missing Features, Found Alternative, No Longer Needed, Too Complicated, Poor Support, Other)" }],
            [{ type: :select, width: "half", label: "Overall Satisfaction (1-5)" }, { type: :select, width: "half", label: "Ease of Use (1-5)" }],
            [{ type: :select, width: "half", label: "Value for Money (1-5)" }, { type: :select, width: "half", label: "Customer Support (1-5)" }],
            [{ type: :checkbox, width: "full", label: "Which Features Did You Use? (Dashboard, Reports, Integrations, API, Automations, Collaboration, Mobile App)" }],
            [{ type: :radio, width: "full", label: "Did you experience any technical issues during your subscription?" }],
            [{ type: :radio, width: "full", label: "Would a discount or adjusted plan change your mind?" }],
            [{ type: :radio, width: "full", label: "Would you recommend us to others despite cancelling?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Comments" }],
            [{ type: :textarea, width: "full", label: "What could we have done better?" }],
            [{ type: :textarea, width: "full", label: "Any other feedback or suggestions?" }],
            [{ type: :checkbox, width: "full", label: "I'm open to being contacted about re-joining in the future" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Account Info", match_types: %w[text email] },
              { label: "Your Feedback", match_types: %w[select radio checkbox] },
              { label: "Comments", match_types: %w[textarea] }
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
