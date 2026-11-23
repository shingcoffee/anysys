# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Tutoring
      module ProgressReport
        DEFINITION = {
          key: "progress_report",
          name: "Student Progress Report",
          description: "Tutor-submitted progress report with skill assessments, goals, and parent communication",
          category: "tutoring",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Session Information" }],
            [{ type: :input, width: "half", label: "Student Name" }, { type: :input, width: "half", label: "Tutor Name" }],
            [{ type: :date, width: "half", label: "Report Date" }, { type: :select, width: "half", label: "Subject / Topic Area" }],
            [{ type: :select, width: "half", label: "Grade Level / Year" }, { type: :number, width: "half", label: "Session Number" }],
            [{ type: :select, width: "half", label: "Session Duration (30 min, 45 min, 60 min, 90 min)" }, { type: :select, width: "half", label: "Session Format (In-Person, Online, Hybrid)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Assessment" }],
            [{ type: :select, width: "half", label: "Overall Progress (1-5)" }, { type: :select, width: "half", label: "Effort & Engagement (1-5)" }],
            [{ type: :select, width: "half", label: "Comprehension Level (Below, At, Above Grade Level)" }, { type: :select, width: "half", label: "Homework Completion (Always, Usually, Sometimes, Never)" }],
            [{ type: :checkbox, width: "full", label: "Skills Demonstrated (Problem Solving, Reading Comprehension, Writing, Critical Thinking, Test-Taking, Active Participation)" }],
            [{ type: :radio, width: "full", label: "Is the student meeting their stated goals?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Feedback & Goals" }],
            [{ type: :textarea, width: "full", label: "Topics Covered This Session" }],
            [{ type: :textarea, width: "full", label: "Strengths Observed" }],
            [{ type: :textarea, width: "full", label: "Areas Needing Improvement" }],
            [{ type: :textarea, width: "full", label: "Goals for Next Session" }],
            [{ type: :textarea, width: "full", label: "Recommended Practice / Homework Assignments" }],
            [{ type: :radio, width: "full", label: "Would you recommend increasing session frequency?" }],
            [{ type: :checkbox, width: "full", label: "Report has been shared with parent / guardian" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "textarea" => "full",
              "radio" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Session Info", match_types: %w[text email date number] },
              { label: "Assessment", match_types: %w[select checkbox radio] },
              { label: "Feedback & Goals", match_types: %w[textarea] }
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
