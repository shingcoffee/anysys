# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Tutoring
      module SessionBooking
        DEFINITION = {
          key: "tutoring_session",
          name: "Tutoring Session Booking",
          description: "Book a tutoring or coaching session with subject, level, and scheduling",
          category: "tutoring",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Student Information" }],
            [{ type: :input, width: "half", label: "Student Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Parent / Guardian Name" }, { type: :input, width: "half", label: "Guardian Phone" }],
            [{ type: :select, width: "half", label: "Grade / Education Level" }, { type: :select, width: "half", label: "School / Institution" }],
            [{ type: :divider }],
            [{ type: :section, label: "Session Details" }],
            [{ type: :select, width: "half", label: "Subject" }, { type: :select, width: "half", label: "Specific Topic / Curriculum" }],
            [{ type: :select, width: "half", label: "Session Type (One-time, Recurring Weekly, Exam Prep, Summer)" }, { type: :select, width: "half", label: "Session Duration (30 min, 60 min, 90 min)" }],
            [{ type: :radio, width: "full", label: "Format (Online, In-Person, Either)" }],
            [{ type: :select, width: "half", label: "Preferred Tutor (if known)" }, { type: :select, width: "half", label: "Language of Instruction" }],
            [{ type: :date, width: "half", label: "Preferred Start Date" }, { type: :select, width: "half", label: "Preferred Time Slot" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time Slot" }],
            [{ type: :divider }],
            [{ type: :section, label: "Goals & Materials" }],
            [{ type: :textarea, width: "full", label: "Topics to Cover / Areas of Difficulty" }],
            [{ type: :textarea, width: "full", label: "Learning Goals & Expected Outcomes" }],
            [{ type: :file, width: "full", label: "Homework, Syllabus, or Study Materials (optional)" }],
            [{ type: :checkbox, width: "full", label: "I agree to the cancellation policy (24-hour notice required)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full",
              "checkbox" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Student & Contact", match_types: %w[text email tel date] },
              { label: "Session Details", match_types: %w[select radio time] },
              { label: "Goals & Materials", match_types: %w[textarea file checkbox] }
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
