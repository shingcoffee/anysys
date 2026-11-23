# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Feedback
      module BugReport
        DEFINITION = {
          key: "bug_report",
          name: "Bug Report",
          description: "Software issue report with severity, steps to reproduce, and screenshots",
          category: "feedback",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Reporter Info" }],
            [{ type: :input, width: "half", label: "Your Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Account / User ID" }, { type: :select, width: "half", label: "Role (Admin, User, Guest, Developer)" }],
            [{ type: :input, width: "half", label: "Company / Organization" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Bug Details" }],
            [{ type: :input, width: "full", label: "Bug Title / Summary" }],
            [{ type: :select, width: "half", label: "Severity (Critical, High, Medium, Low)" }, { type: :select, width: "half", label: "Category (UI, Backend, API, Performance, Security, Data, Other)" }],
            [{ type: :input, width: "half", label: "App / Product Version" }, { type: :input, width: "half", label: "Browser / App Platform" }],
            [{ type: :input, width: "half", label: "Operating System & Version" }, { type: :select, width: "half", label: "Environment (Production, Staging, Dev)" }],
            [{ type: :select, width: "half", label: "Frequency (Always, Sometimes, Randomly, Once)" }, { type: :radio, width: "half", label: "Can you reproduce this bug?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Description" }],
            [{ type: :textarea, width: "full", label: "Steps to Reproduce" }],
            [{ type: :textarea, width: "full", label: "Expected Behavior" }],
            [{ type: :textarea, width: "full", label: "Actual Behavior" }],
            [{ type: :textarea, width: "full", label: "Any workaround found?" }],
            [{ type: :file, width: "full", label: "Upload Screenshots or Screen Recording" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Reporter Info", match_types: %w[text email select] },
              { label: "Bug Details", match_types: %w[radio] },
              { label: "Description", match_types: %w[textarea file] }
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
