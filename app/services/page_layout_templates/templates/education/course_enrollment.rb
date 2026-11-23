# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Education
      module CourseEnrollment
        DEFINITION = {
          key: "course_enrollment",
          name: "Course Enrollment",
          description: "Student enrollment with course selection and academic details",
          category: "education",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Student Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Student ID" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :select, width: "half", label: "Year of Study (Freshman, Sophomore, Junior, Senior, Graduate)" }],
            [{ type: :select, width: "half", label: "Program / Major" }, { type: :select, width: "half", label: "Advisor Name" }],
            [{ type: :divider }],
            [{ type: :section, label: "Course Selection" }],
            [{ type: :select, width: "half", label: "Semester / Term" }, { type: :select, width: "half", label: "Delivery Mode (In-Person, Online, Hybrid)" }],
            [{ type: :select, width: "half", label: "Course Name" }, { type: :input, width: "half", label: "Course Code" }],
            [{ type: :select, width: "half", label: "Section / Schedule" }, { type: :select, width: "half", label: "Credit Hours" }],
            [{ type: :radio, width: "full", label: "Full-time or Part-time enrollment?" }],
            [{ type: :radio, width: "full", label: "Have you completed the prerequisites for this course?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Additional Information" }],
            [{ type: :textarea, width: "full", label: "Prior Experience / Prerequisites Completed" }],
            [{ type: :textarea, width: "full", label: "Accessibility or Accommodation Needs" }],
            [{ type: :file, width: "full", label: "Upload Supporting Documents (Transcript, Prerequisite Waiver)" }],
            [{ type: :checkbox, width: "full", label: "I have reviewed and meet the course prerequisites and agree to the enrollment terms" }]
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
              "checkbox" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Student Information", match_types: %w[text email tel date select url] },
              { label: "Course Selection", match_types: %w[radio] },
              { label: "Additional", match_types: %w[textarea checkbox file] }
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
