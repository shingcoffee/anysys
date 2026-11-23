# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Survey
      module QuizAssessment
        DEFINITION = {
          key: "quiz_assessment",
          name: "Quiz / Assessment",
          description: "Multiple-choice questions with structured answer groups",
          category: "survey",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Participant Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Quiz / Course Code" }, { type: :date, width: "half", label: "Date" }],
            [{ type: :divider }],
            [{ type: :section, label: "Section 1 — Multiple Choice" }],
            [{ type: :radio, width: "full", label: "Question 1: Select the correct answer" }],
            [{ type: :radio, width: "full", label: "Question 2: Select the correct answer" }],
            [{ type: :radio, width: "full", label: "Question 3: Select the correct answer" }],
            [{ type: :divider }],
            [{ type: :section, label: "Section 2 — Select All That Apply" }],
            [{ type: :checkbox, width: "full", label: "Question 4: Select all that apply" }],
            [{ type: :checkbox, width: "full", label: "Question 5: Select all that apply" }],
            [{ type: :divider }],
            [{ type: :section, label: "Section 3 — Short Answer" }],
            [{ type: :textarea, width: "full", label: "Question 6: Provide a brief explanation" }],
            [{ type: :textarea, width: "full", label: "Question 7: Describe your answer" }],
            [{ type: :checkbox, width: "full", label: "I confirm this is my own work and I have not used unauthorized assistance" }]
          ],
          layout: {
            default_width: "full",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Participant", match_types: %w[text email date] },
              { label: "Questions", match_types: %w[radio checkbox textarea] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
