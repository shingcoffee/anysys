# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Saas
      module BetaSignup
        DEFINITION = {
          key: "beta_signup",
          name: "Beta Signup",
          description: "Early access waitlist with use case, company size, and feature interest",
          category: "saas",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "About You" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Work Email" }],
            [{ type: :input, width: "half", label: "Company / Organization" }, { type: :input, width: "half", label: "Job Title" }],
            [{ type: :input, width: "half", label: "Company Website (optional)" }, { type: :select, width: "half", label: "Country" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Needs" }],
            [{ type: :select, width: "half", label: "Company Size (1-10, 11-50, 51-200, 201-500, 500+)" }, { type: :select, width: "half", label: "Industry" }],
            [{ type: :select, width: "half", label: "Primary Use Case" }, { type: :select, width: "half", label: "Current Solution / Tool" }],
            [{ type: :select, width: "half", label: "Monthly Budget for Tools (< $100, $100-$500, $500-$1K, $1K+)" }, { type: :select, width: "half", label: "Team Size Using This Tool" }],
            [{ type: :checkbox, width: "full", label: "Features You're Most Interested In" }],
            [{ type: :select, width: "half", label: "How did you hear about us?" }, { type: :input, width: "half", label: "Referral Name (if any)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Additional Info" }],
            [{ type: :textarea, width: "full", label: "What problem are you trying to solve?" }],
            [{ type: :radio, width: "full", label: "Would you be willing to participate in user research or interviews?" }],
            [{ type: :checkbox, width: "full", label: "I agree to receive product updates and beta program communications" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "number" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "url" => "half",
            },
            sections: [
              { label: "About You", match_types: %w[text email url] },
              { label: "Your Needs", match_types: %w[select checkbox] },
              { label: "Additional Info", match_types: %w[textarea radio] }
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
