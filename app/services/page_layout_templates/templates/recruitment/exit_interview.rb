# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Recruitment
      module ExitInterview
        DEFINITION = {
          key: "exit_interview",
          name: "Exit Interview",
          description: "Employee exit interview with departure reasons, satisfaction ratings, and improvement suggestions",
          category: "recruitment",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Employee Information" }],
            [{ type: :input, width: "half", label: "Employee Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :input, width: "half", label: "Department" }, { type: :input, width: "half", label: "Job Title" }],
            [{ type: :input, width: "half", label: "Direct Manager" }, { type: :input, width: "half", label: "Years of Service" }],
            [{ type: :date, width: "half", label: "Start Date" }, { type: :date, width: "half", label: "Last Day" }],
            [{ type: :select, width: "half", label: "Employment Type (Full-Time, Part-Time, Contract)" }, { type: :select, width: "half", label: "Work Location (On-Site, Remote, Hybrid)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Experience Ratings" }],
            [{ type: :select, width: "half", label: "Primary Reason for Leaving" }, { type: :select, width: "half", label: "Next Opportunity (New Job, Relocation, Career Change, Education, Personal, Retirement)" }],
            [{ type: :select, width: "half", label: "Overall Job Satisfaction (1-5)" }, { type: :select, width: "half", label: "Management Satisfaction (1-5)" }],
            [{ type: :select, width: "half", label: "Work-Life Balance (1-5)" }, { type: :select, width: "half", label: "Growth & Development Opportunities (1-5)" }],
            [{ type: :select, width: "half", label: "Compensation & Benefits (1-5)" }, { type: :select, width: "half", label: "Team & Culture (1-5)" }],
            [{ type: :checkbox, width: "full", label: "Factors that Influenced Your Decision (Compensation, Culture, Management, Career Growth, Work-Life Balance, Commute, Company Direction, Personal)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Feedback" }],
            [{ type: :textarea, width: "full", label: "What did you enjoy most about working here?" }],
            [{ type: :textarea, width: "full", label: "What could the company improve?" }],
            [{ type: :textarea, width: "full", label: "Suggestions for Your Replacement or Team" }],
            [{ type: :radio, width: "full", label: "Would you recommend this company to others?" }],
            [{ type: :radio, width: "full", label: "Would you consider returning in the future?" }],
            [{ type: :checkbox, width: "full", label: "I consent to this interview being used anonymously for HR reporting purposes" }]
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
              "checkbox" => "full"
            },
            sections: [
              { label: "Employee Info", match_types: %w[text email date] },
              { label: "Experience Ratings", match_types: %w[select checkbox] },
              { label: "Feedback", match_types: %w[textarea radio] }
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
