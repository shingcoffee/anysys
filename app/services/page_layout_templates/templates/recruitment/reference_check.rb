# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Recruitment
      module ReferenceCheck
        DEFINITION = {
          key: "reference_check",
          name: "Reference Check",
          description: "Professional reference questionnaire with performance and character assessment",
          category: "recruitment",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Reference Provider Information" }],
            [{ type: :input, width: "half", label: "Your Full Name" }, { type: :input, width: "half", label: "Your Job Title" }],
            [{ type: :input, width: "half", label: "Company / Organization" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :select, width: "half", label: "Preferred Contact Method" }],
            [{ type: :divider }],
            [{ type: :section, label: "Candidate Relationship" }],
            [{ type: :input, width: "half", label: "Candidate Full Name" }, { type: :select, width: "half", label: "Your Relationship (Manager, Colleague, Direct Report, Client, Other)" }],
            [{ type: :number, width: "half", label: "Years Known" }, { type: :select, width: "half", label: "How Closely Did You Work Together?" }],
            [{ type: :input, width: "half", label: "Candidate's Role / Title" }, { type: :input, width: "half", label: "Department / Team" }],
            [{ type: :date, width: "half", label: "Employment Start (approx.)" }, { type: :date, width: "half", label: "Employment End (approx.)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Performance Assessment" }],
            [{ type: :select, width: "half", label: "Overall Performance Rating" }, { type: :select, width: "half", label: "Communication Skills" }],
            [{ type: :select, width: "half", label: "Teamwork & Collaboration" }, { type: :select, width: "half", label: "Problem-Solving Ability" }],
            [{ type: :select, width: "half", label: "Reliability & Punctuality" }, { type: :select, width: "half", label: "Leadership Qualities" }],
            [{ type: :textarea, width: "full", label: "Key Strengths" }],
            [{ type: :textarea, width: "full", label: "Areas for Growth or Development" }],
            [{ type: :textarea, width: "full", label: "Significant Accomplishments or Contributions" }],
            [{ type: :radio, width: "full", label: "Would You Rehire This Person If Given the Opportunity?" }],
            [{ type: :textarea, width: "full", label: "Any additional comments?" }],
            [{ type: :checkbox, width: "full", label: "I confirm this information is accurate to the best of my knowledge" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "number" => "half",
              "date" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Reference Details", match_types: %w[text email tel] },
              { label: "Relationship & Assessment", match_types: %w[select number date radio] },
              { label: "Comments", match_types: %w[textarea checkbox] }
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
