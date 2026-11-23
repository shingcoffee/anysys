# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Survey
      module EmployeeSatisfaction
        DEFINITION = {
          key: "employee_satisfaction",
          name: "Employee Satisfaction",
          description: "Internal HR survey with engagement scores and department feedback",
          category: "survey",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "About You" }],
            [{ type: :select, width: "half", label: "Department" }, { type: :select, width: "half", label: "Tenure (< 1 yr, 1-3 yrs, 3-5 yrs, 5+ yrs)" }],
            [{ type: :select, width: "half", label: "Employment Type (Full-time, Part-time, Contractor)" }, { type: :select, width: "half", label: "Office Location / Remote" }],
            [{ type: :divider }],
            [{ type: :section, label: "Satisfaction Ratings" }],
            [{ type: :select, width: "half", label: "Overall Job Satisfaction (1-5)" }, { type: :select, width: "half", label: "Work-Life Balance" }],
            [{ type: :select, width: "half", label: "Management & Leadership" }, { type: :select, width: "half", label: "Team Collaboration" }],
            [{ type: :select, width: "half", label: "Growth & Career Development" }, { type: :select, width: "half", label: "Compensation & Benefits" }],
            [{ type: :select, width: "half", label: "Workplace Culture" }, { type: :select, width: "half", label: "Resources & Tools Provided" }],
            [{ type: :radio, width: "full", label: "Would you recommend this company as a great place to work?" }],
            [{ type: :radio, width: "full", label: "Do you feel valued and recognized for your contributions?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Open Feedback" }],
            [{ type: :textarea, width: "full", label: "What do you enjoy most about working here?" }],
            [{ type: :textarea, width: "full", label: "What could be improved?" }],
            [{ type: :textarea, width: "full", label: "Any other suggestions or comments?" }],
            [{ type: :checkbox, width: "full", label: "This survey is anonymous — I understand my responses will be aggregated" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "range" => "full",
            },
            sections: [
              { label: "About You", match_types: %w[select] },
              { label: "Ratings", match_types: %w[radio range] },
              { label: "Open Feedback", match_types: %w[textarea checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
