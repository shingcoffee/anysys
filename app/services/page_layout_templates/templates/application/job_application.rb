# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Application
      module JobApplication
        DEFINITION = {
          key: "job_application",
          name: "Job Application",
          description: "Hiring form with personal details, resume upload, and cover letter",
          category: "application",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Personal Details" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Current Address (Street, City, State, ZIP)" }],
            [{ type: :input, width: "half", label: "LinkedIn Profile URL" }, { type: :input, width: "half", label: "Personal Website / Portfolio" }],
            [{ type: :divider }],
            [{ type: :section, label: "Application Details" }],
            [{ type: :select, width: "half", label: "Position Applying For" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :select, width: "half", label: "Desired Employment Type (Full-Time, Part-Time, Contract)" }, { type: :input, width: "half", label: "Desired Salary Range" }],
            [{ type: :date, width: "half", label: "Date Available to Start" }, { type: :radio, width: "half", label: "Willing to Relocate?" }],
            [{ type: :radio, width: "full", label: "Are you legally authorized to work in the U.S.?" }],
            [{ type: :radio, width: "full", label: "Will you require employment visa sponsorship now or in the future?" }],
            [{ type: :input, width: "half", label: "Current / Most Recent Employer" }, { type: :input, width: "half", label: "Job Title" }],
            [{ type: :date, width: "half", label: "Employment Start Date" }, { type: :date, width: "half", label: "Employment End Date (or Present)" }],
            [{ type: :textarea, width: "full", label: "Key Responsibilities & Achievements" }],
            [{ type: :number, width: "half", label: "Total Years of Relevant Experience" }, { type: :select, width: "half", label: "Highest Level of Education" }],
            [{ type: :input, width: "half", label: "School / University Name" }, { type: :input, width: "half", label: "Degree / Major" }],
            [{ type: :date, width: "half", label: "Graduation Date (or Expected)" }, { type: :input, width: "half", label: "GPA (optional)" }],
            [{ type: :input, width: "half", label: "Reference 1 Name & Contact" }, { type: :input, width: "half", label: "Reference 2 Name & Contact" }],
            [{ type: :divider }],
            [{ type: :section, label: "Documents & Cover Letter" }],
            [{ type: :textarea, width: "full", label: "Technical Skills, Languages, and Certifications" }],
            [{ type: :file, width: "full", label: "Resume / CV (PDF or Word)" }],
            [{ type: :file, width: "full", label: "Cover Letter (optional)" }],
            [{ type: :file, width: "full", label: "Additional Documents (Transcripts, Portfolio, Certifications)" }],
            [{ type: :textarea, width: "full", label: "Why are you interested in this position and why are you a great fit?" }],
            [{ type: :checkbox, width: "full", label: "I certify that all information provided is accurate and complete to the best of my knowledge" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "file" => "full",
              "textarea" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Personal Details", match_types: %w[text email tel url] },
              { label: "Application Details", match_types: %w[select date number radio datetime-local] },
              { label: "Documents & Cover Letter", match_types: %w[file textarea checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
