# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hoa
      module ViolationReport
        DEFINITION = {
          key: "hoa_violation_report",
          name: "HOA Violation Report",
          description: "Community covenant violation report with location, type of violation, and photo evidence",
          category: "hoa",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Reporter Information" }],
            [{ type: :input, width: "half", label: "Reporter Name (optional)" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Your Unit / Lot Number" }],
            [{ type: :checkbox, width: "full", label: "I wish to remain anonymous (your identity will not be shared with the violating party)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Violation Details" }],
            [{ type: :input, width: "full", label: "Violation Address / Location" }],
            [{ type: :select, width: "half", label: "Violation Type (Parking, Landscaping, Noise, Pets, Trash, Unapproved Structure, Exterior, Other)" }, { type: :date, width: "half", label: "Date Observed" }],
            [{ type: :select, width: "half", label: "Time of Day (if relevant)" }, { type: :select, width: "half", label: "Estimated Duration of Violation" }],
            [{ type: :radio, width: "full", label: "Is this a recurring issue?" }],
            [{ type: :radio, width: "full", label: "Have you spoken with the homeowner?" }],
            [{ type: :textarea, width: "full", label: "Description of the Violation" }],
            [{ type: :divider }],
            [{ type: :section, label: "Evidence & Follow-up" }],
            [{ type: :file, width: "full", label: "Photos or Videos of Violation" }],
            [{ type: :radio, width: "full", label: "Would you like to be notified of the outcome?" }],
            [{ type: :textarea, width: "full", label: "Any additional context or information" }]
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
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Reporter Info", match_types: %w[text email tel] },
              { label: "Violation Details", match_types: %w[select date radio textarea] },
              { label: "Evidence & Follow-up", match_types: %w[file checkbox] }
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
