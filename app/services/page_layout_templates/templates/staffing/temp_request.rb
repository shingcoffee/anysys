# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Staffing
      module TempRequest
        DEFINITION = {
          key: "temp_staffing_request",
          name: "Temporary Staffing Request",
          description: "Temp staffing request with position details, skill requirements, duration, and work schedule",
          category: "staffing",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Company & Contact" }],
            [{ type: :input, width: "half", label: "Company Name" }, { type: :input, width: "half", label: "Contact Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Work Location Address" }],
            [{ type: :input, width: "half", label: "Billing Contact (if different)" }, { type: :input, width: "half", label: "PO Number / Cost Center" }],
            [{ type: :divider }],
            [{ type: :section, label: "Position Details" }],
            [{ type: :input, width: "half", label: "Job Title / Role" }, { type: :select, width: "half", label: "Industry / Sector" }],
            [{ type: :number, width: "half", label: "Number of Workers Needed" }, { type: :select, width: "half", label: "Shift Type (Day, Evening, Night, Split, Rotating)" }],
            [{ type: :date, width: "half", label: "Start Date" }, { type: :date, width: "half", label: "Estimated End Date" }],
            [{ type: :select, width: "half", label: "Pay Rate / Range" }, { type: :select, width: "half", label: "Experience Level (Entry, Mid, Senior, Expert)" }],
            [{ type: :select, width: "half", label: "Work Hours per Week" }, { type: :select, width: "half", label: "Work Environment (On-Site, Remote, Hybrid)" }],
            [{ type: :checkbox, width: "full", label: "Required Skills / Certifications (Forklift, OSHA 10/30, First Aid, CDL, Microsoft Office, CPA, PMP, Other)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Description & Requirements" }],
            [{ type: :textarea, width: "full", label: "Job Description and Responsibilities" }],
            [{ type: :radio, width: "full", label: "Drug screening required?" }],
            [{ type: :radio, width: "full", label: "Background check required?" }],
            [{ type: :radio, width: "full", label: "Possibility of permanent hire after assignment?" }],
            [{ type: :textarea, width: "full", label: "Additional Requirements or Notes" }]
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
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Company & Contact", match_types: %w[text email tel] },
              { label: "Position Details", match_types: %w[number select date checkbox] },
              { label: "Description & Requirements", match_types: %w[radio textarea file] }
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
