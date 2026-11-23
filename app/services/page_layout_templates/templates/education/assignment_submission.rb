# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Education
      module AssignmentSubmission
        DEFINITION = {
          key: "assignment_submission",
          name: "Assignment Submission",
          description: "Student submission form with file upload and comments",
          category: "education",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Student Details" }],
            [{ type: :input, width: "half", label: "Student Full Name" }, { type: :input, width: "half", label: "Student ID" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :select, width: "half", label: "Course / Class" }, { type: :select, width: "half", label: "Section / Period" }],
            [{ type: :select, width: "half", label: "Instructor Name" }, { type: :select, width: "half", label: "Term / Semester" }],
            [{ type: :divider }],
            [{ type: :section, label: "Assignment Details" }],
            [{ type: :select, width: "half", label: "Assignment Name / Title" }, { type: :date, width: "half", label: "Submission Date" }],
            [{ type: :select, width: "half", label: "Assignment Type (Essay, Project, Lab Report, Problem Set, Presentation, Other)" }, { type: :select, width: "half", label: "Submission Type (Individual, Group)" }],
            [{ type: :input, width: "full", label: "Group Member Names (if group submission)" }],
            [{ type: :radio, width: "full", label: "Is this a late submission?" }],
            [{ type: :textarea, width: "full", label: "Reason for Late Submission (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Submission" }],
            [{ type: :file, width: "full", label: "Upload Assignment File(s) (PDF, DOCX, ZIP)" }],
            [{ type: :textarea, width: "full", label: "Comments or Notes to Instructor" }],
            [{ type: :checkbox, width: "full", label: "I affirm this work is my own, properly cited, and complies with the academic honor code" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "file" => "full",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Student Details", match_types: %w[text email tel select date] },
              { label: "Assignment Details", match_types: %w[radio textarea] },
              { label: "Submission", match_types: %w[file checkbox] }
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
