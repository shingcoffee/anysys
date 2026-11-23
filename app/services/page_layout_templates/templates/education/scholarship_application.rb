# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Education
      module ScholarshipApplication
        DEFINITION = {
          key: "scholarship_application",
          name: "Scholarship Application",
          description: "Academic scholarship with GPA, essay, and recommendation letter upload",
          category: "education",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Student Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Student ID" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :select, width: "half", label: "Year of Study (Freshman, Sophomore, Junior, Senior, Graduate)" }],
            [{ type: :select, width: "half", label: "Program / Major" }, { type: :number, width: "half", label: "Current GPA (out of 4.0)" }],
            [{ type: :select, width: "half", label: "Enrollment Status (Full-Time, Part-Time)" }, { type: :input, width: "half", label: "Expected Graduation Date" }],
            [{ type: :divider }],
            [{ type: :section, label: "Scholarship Details" }],
            [{ type: :select, width: "half", label: "Scholarship Name / Category" }, { type: :select, width: "half", label: "Academic Year Applying For" }],
            [{ type: :number, width: "half", label: "Household Annual Income ($)" }, { type: :number, width: "half", label: "Number of Dependents in Household" }],
            [{ type: :radio, width: "full", label: "Are you a first-generation college student?" }],
            [{ type: :radio, width: "full", label: "Do you hold any other scholarships or financial aid?" }],
            [{ type: :checkbox, width: "full", label: "Extracurricular Activities (Student Government, Sports, Clubs, Volunteering, Work, Research, Honors Society, Other)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Essays & Documents" }],
            [{ type: :textarea, width: "full", label: "Personal Statement: Why do you deserve this scholarship?" }],
            [{ type: :textarea, width: "full", label: "Describe your financial need and how this scholarship will help achieve your goals" }],
            [{ type: :textarea, width: "full", label: "Describe your community involvement and leadership experience" }],
            [{ type: :file, width: "full", label: "Upload Official Transcript (required)" }],
            [{ type: :file, width: "full", label: "Upload Recommendation Letter(s)" }],
            [{ type: :file, width: "full", label: "Additional Supporting Documents (optional)" }],
            [{ type: :checkbox, width: "full", label: "I certify all information provided is accurate and complete, and I meet the eligibility criteria" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Student Information", match_types: %w[text email tel number date select url] },
              { label: "Scholarship Details", match_types: %w[radio checkbox] },
              { label: "Essays & Documents", match_types: %w[textarea file] }
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
