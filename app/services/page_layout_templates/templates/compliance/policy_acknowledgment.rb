# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Compliance
      module PolicyAcknowledgment
        DEFINITION = {
          key: "policy_acknowledgment",
          name: "Policy Acknowledgment",
          description: "Employee policy review and acknowledgment with digital signature and comprehension confirmation",
          category: "compliance",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Employee Information" }],
            [{ type: :input, width: "half", label: "Employee Full Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :input, width: "half", label: "Department" }, { type: :input, width: "half", label: "Job Title" }],
            [{ type: :input, width: "half", label: "Manager / Supervisor Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :select, width: "half", label: "Employment Type (Full-Time, Part-Time, Contractor, Intern)" }, { type: :date, width: "half", label: "Date of Acknowledgment" }],
            [{ type: :divider }],
            [{ type: :section, label: "Policy Document" }],
            [{ type: :select, width: "full", label: "Policy Name (Code of Conduct, Data Privacy, Anti-Harassment, Remote Work, IT Security, Expense Policy, Other)" }],
            [{ type: :input, width: "half", label: "Policy Version / Revision #" }, { type: :date, width: "half", label: "Policy Effective Date" }],
            [{ type: :radio, width: "full", label: "Have you received and reviewed the complete policy document?" }],
            [{ type: :radio, width: "full", label: "Do you have any questions or require clarification?" }],
            [{ type: :textarea, width: "full", label: "Questions, Concerns, or Comments (if any)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Acknowledgment & Signature" }],
            [{ type: :checkbox, width: "full", label: "I have read and understand the policy in its entirety" }],
            [{ type: :checkbox, width: "full", label: "I agree to comply with all requirements outlined in this policy" }],
            [{ type: :checkbox, width: "full", label: "I understand the consequences of non-compliance, including disciplinary action" }],
            [{ type: :checkbox, width: "full", label: "I have had the opportunity to ask questions and received satisfactory answers" }],
            [{ type: :signature, width: "full", label: "Employee Signature" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "date" => "half",
              "select" => "full",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
            },
            sections: [
              { label: "Employee Info", match_types: %w[text email date select] },
              { label: "Policy & Questions", match_types: %w[radio textarea] },
              { label: "Acknowledgment & Signature", match_types: %w[checkbox] }
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
