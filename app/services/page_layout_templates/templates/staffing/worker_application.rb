# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Staffing
      module WorkerApplication
        DEFINITION = {
          key: "staffing_worker_application",
          name: "Staffing Worker Application",
          description: "Worker registration for temp agency with availability, skills, work history, and certification uploads",
          category: "staffing",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :select, width: "half", label: "Highest Education Level" }, { type: :select, width: "half", label: "Years of Work Experience" }],
            [{ type: :divider }],
            [{ type: :section, label: "Work Preferences" }],
            [{ type: :checkbox, width: "full", label: "Industries of Interest (Manufacturing, Warehousing, Healthcare, Administrative, IT, Hospitality, Construction, Retail, Other)" }],
            [{ type: :checkbox, width: "full", label: "Available Shifts (Day, Evening, Night, Weekends, Holidays, On-Call, Rotating)" }],
            [{ type: :select, width: "half", label: "Transportation (Own Vehicle, Public Transit, Rideshare, Bicycle)" }, { type: :select, width: "half", label: "Max Travel Radius (5 mi, 10 mi, 25 mi, 50 mi, No Limit)" }],
            [{ type: :date, width: "half", label: "Available Starting" }, { type: :select, width: "half", label: "Desired Hourly Pay Rate" }],
            [{ type: :select, width: "half", label: "Work Authorization (US Citizen, Permanent Resident, Work Visa, Other)" }, { type: :radio, width: "half", label: "Open to permanent placement?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Experience & Documents" }],
            [{ type: :checkbox, width: "full", label: "Skills & Certifications (Forklift, OSHA 10, CPR/First Aid, CDL, Microsoft Office, Data Entry, Customer Service, Other)" }],
            [{ type: :textarea, width: "full", label: "Work Experience Summary (most recent first)" }],
            [{ type: :file, width: "full", label: "Upload Resume and/or Certifications" }],
            [{ type: :radio, width: "full", label: "Legally authorized to work in this country?" }],
            [{ type: :checkbox, width: "full", label: "I consent to background check and drug screening as required by placement employers" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Personal Information", match_types: %w[text email tel date] },
              { label: "Work Preferences", match_types: %w[select checkbox radio] },
              { label: "Experience & Documents", match_types: %w[textarea file] }
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
