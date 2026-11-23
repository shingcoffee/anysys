# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hr
      module PerformanceReview
        DEFINITION = {
          key: "performance_review",
          name: "Performance Review",
          description: "Quarterly or annual employee evaluation with goals and ratings",
          category: "hr",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Employee Info" }],
            [{ type: :input, width: "half", label: "Employee Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :input, width: "half", label: "Job Title" }, { type: :select, width: "half", label: "Department" }],
            [{ type: :input, width: "half", label: "Reviewer Name" }, { type: :select, width: "half", label: "Reviewer Title / Relationship" }],
            [{ type: :select, width: "half", label: "Review Period (Q1, Q2, Q3, Q4, Annual, Mid-Year)" }, { type: :date, width: "half", label: "Review Date" }],
            [{ type: :select, width: "half", label: "Employment Type (Full-Time, Part-Time, Contract)" }, { type: :select, width: "half", label: "Years in Current Role" }],
            [{ type: :divider }],
            [{ type: :section, label: "Performance Ratings" }],
            [{ type: :select, width: "half", label: "Job Knowledge & Technical Skills (1-5)" }, { type: :select, width: "half", label: "Quality of Work (1-5)" }],
            [{ type: :select, width: "half", label: "Communication (1-5)" }, { type: :select, width: "half", label: "Teamwork & Collaboration (1-5)" }],
            [{ type: :select, width: "half", label: "Attendance & Reliability (1-5)" }, { type: :select, width: "half", label: "Initiative & Problem Solving (1-5)" }],
            [{ type: :select, width: "half", label: "Leadership & Management (1-5)" }, { type: :select, width: "half", label: "Overall Performance (1-5)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Comments & Goals" }],
            [{ type: :textarea, width: "full", label: "Key Achievements This Review Period" }],
            [{ type: :textarea, width: "full", label: "Areas for Improvement" }],
            [{ type: :textarea, width: "full", label: "Goals for Next Review Period" }],
            [{ type: :textarea, width: "full", label: "Training & Development Recommendations" }],
            [{ type: :select, width: "half", label: "Promotion Recommendation?" }, { type: :select, width: "half", label: "Salary Adjustment Recommended?" }],
            [{ type: :checkbox, width: "full", label: "Employee acknowledges receipt and has reviewed this performance evaluation" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "date" => "half",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Employee Info", match_types: %w[text email select date] },
              { label: "Performance Ratings", match_types: %w[] },
              { label: "Comments & Goals", match_types: %w[textarea checkbox] }
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
