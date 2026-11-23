# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Legal
      module IncidentReport
        DEFINITION = {
          key: "incident_report",
          name: "Incident Report",
          description: "Workplace incident form with date/time, witnesses, and photo upload",
          category: "legal",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Reporter Info" }],
            [{ type: :input, width: "half", label: "Reporter Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :input, width: "half", label: "Department" }, { type: :input, width: "half", label: "Phone / Email" }],
            [{ type: :input, width: "half", label: "Job Title" }, { type: :select, width: "half", label: "Employment Type (Full-Time, Part-Time, Contract, Visitor)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Incident Details" }],
            [{ type: :date, width: "half", label: "Date of Incident" }, { type: :input, width: "half", label: "Time of Incident" }],
            [{ type: :input, width: "full", label: "Location of Incident (Building, Floor, Area)" }],
            [{ type: :select, width: "half", label: "Incident Type (Injury, Near Miss, Property Damage, Security, Environmental, Fire, Other)" }, { type: :select, width: "half", label: "Severity (Minor, Moderate, Serious, Critical)" }],
            [{ type: :textarea, width: "full", label: "What Happened? (Describe in Detail)" }],
            [{ type: :textarea, width: "full", label: "What Caused the Incident? (Root Cause)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Evidence & Signature" }],
            [{ type: :input, width: "full", label: "Persons Injured / Affected (Names, Job Titles)" }],
            [{ type: :textarea, width: "full", label: "Witnesses (Names, Contact Information)" }],
            [{ type: :radio, width: "full", label: "Was medical treatment required?" }],
            [{ type: :textarea, width: "full", label: "Immediate Actions Taken" }],
            [{ type: :radio, width: "full", label: "Has the hazard been eliminated or controlled?" }],
            [{ type: :file, width: "full", label: "Upload Photos, Videos, or Evidence" }],
            [{ type: :signature, width: "full", label: "Reporter Signature" }]
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
              "time" => "half",
              "datetime-local" => "half",
            },
            sections: [
              { label: "Reporter Info", match_types: %w[text email tel select] },
              { label: "Incident Details", match_types: %w[date textarea time datetime-local] },
              { label: "Evidence & Signature", match_types: %w[radio file] }
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
