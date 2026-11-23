# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Feedback
      module FeatureRequest
        DEFINITION = {
          key: "feature_request",
          name: "Feature Request",
          description: "Product feature suggestion with priority, use case, and voting",
          category: "feedback",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Submitter Info" }],
            [{ type: :input, width: "half", label: "Your Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :select, width: "half", label: "Your Role (Admin, User, Guest, Developer)" }, { type: :input, width: "half", label: "Company / Organization" }],
            [{ type: :input, width: "half", label: "Product / Plan you are on" }, { type: :select, width: "half", label: "How long have you been a customer?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Feature Details" }],
            [{ type: :input, width: "full", label: "Feature Title / Summary" }],
            [{ type: :select, width: "half", label: "Category (UI/UX, API, Performance, Integration, Reporting, Security, Other)" }, { type: :select, width: "half", label: "Priority (Nice to Have, Important, Critical)" }],
            [{ type: :textarea, width: "full", label: "Describe the Feature Request" }],
            [{ type: :textarea, width: "full", label: "Problem It Solves / Use Case" }],
            [{ type: :textarea, width: "full", label: "Proposed Solution or Approach (optional)" }],
            [{ type: :radio, width: "full", label: "How often do you encounter this problem?" }],
            [{ type: :select, width: "half", label: "Business Impact (Low, Medium, High, Critical)" }, { type: :number, width: "half", label: "Estimated Number of Users Affected" }],
            [{ type: :file, width: "full", label: "Upload Mockups, Wireframes, or References (optional)" }],
            [{ type: :checkbox, width: "full", label: "I would like to be notified when this feature is available" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Submitter Info", match_types: %w[text email select] },
              { label: "Feature Details", match_types: %w[textarea radio number] },
              { label: "Attachments & Notifications", match_types: %w[file checkbox] }
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
