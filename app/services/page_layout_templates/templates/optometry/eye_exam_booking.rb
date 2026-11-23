# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Optometry
      module EyeExamBooking
        DEFINITION = {
          key: "eye_exam_booking",
          name: "Eye Exam Booking",
          description: "Optometry appointment with vision concerns, insurance, and prescription history",
          category: "optometry",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Patient Information" }],
            [{ type: :input, width: "half", label: "Patient Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :select, width: "half", label: "Gender" }, { type: :select, width: "half", label: "Preferred Language" }],
            [{ type: :divider }],
            [{ type: :section, label: "Vision & Medical History" }],
            [{ type: :select, width: "half", label: "Exam Type (Comprehensive, Contact Lens, Follow-up, Emergency)" }, { type: :select, width: "half", label: "Last Eye Exam (< 1 yr, 1-2 yrs, 2-5 yrs, Never)" }],
            [{ type: :checkbox, width: "full", label: "Vision Concerns (Blurry Vision, Eye Strain, Headaches, Floaters, Dry Eyes, Light Sensitivity, Redness)" }],
            [{ type: :radio, width: "full", label: "Currently wear glasses or contact lenses?" }],
            [{ type: :radio, width: "full", label: "Any family history of eye disease (glaucoma, macular degeneration)?" }],
            [{ type: :textarea, width: "full", label: "Current Medications or Known Allergies" }],
            [{ type: :divider }],
            [{ type: :section, label: "Insurance & Scheduling" }],
            [{ type: :radio, width: "full", label: "Have vision insurance?" }],
            [{ type: :input, width: "half", label: "Insurance Provider" }, { type: :input, width: "half", label: "Member ID / Group Number" }],
            [{ type: :date, width: "half", label: "Preferred Appointment Date" }, { type: :select, width: "half", label: "Preferred Time" }],
            [{ type: :radio, width: "full", label: "Is this a new patient visit?" }],
            [{ type: :textarea, width: "full", label: "Additional Concerns or Notes" }]
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
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Patient Info", match_types: %w[text email tel date select] },
              { label: "Vision & Insurance", match_types: %w[checkbox radio] },
              { label: "Scheduling", match_types: %w[textarea] }
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
