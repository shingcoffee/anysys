# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Consulting
      module ProjectBrief
        DEFINITION = {
          key: "project_brief",
          name: "Project Brief",
          description: "Client project brief with objectives, scope, timeline, and budget",
          category: "consulting",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Client Information" }],
            [{ type: :input, width: "half", label: "Company Name" }, { type: :input, width: "half", label: "Primary Contact Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Industry" }, { type: :select, width: "half", label: "Company Size (1-10, 11-50, 51-200, 200+)" }],
            [{ type: :input, width: "half", label: "Primary Contact Job Title" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Project Details" }],
            [{ type: :input, width: "full", label: "Project Title" }],
            [{ type: :select, width: "half", label: "Project Type (Consulting, Research, Implementation, Training, Audit)" }, { type: :select, width: "half", label: "Priority Level (High, Medium, Low)" }],
            [{ type: :textarea, width: "full", label: "Project Background & Context" }],
            [{ type: :textarea, width: "full", label: "Project Objectives & Success Criteria" }],
            [{ type: :textarea, width: "full", label: "Scope of Work & Key Deliverables" }],
            [{ type: :textarea, width: "full", label: "Key Constraints, Dependencies, or Risks" }],
            [{ type: :checkbox, width: "full", label: "Stakeholders Involved (Executive, Finance, IT, HR, Operations, Legal, Marketing)" }],
            [{ type: :date, width: "half", label: "Desired Start Date" }, { type: :date, width: "half", label: "Target Completion Date" }],
            [{ type: :select, width: "half", label: "Budget Range" }, { type: :radio, width: "half", label: "Has budget been approved?" }],
            [{ type: :file, width: "full", label: "Upload Supporting Documents (RFP, Specs, Previous Reports)" }]
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
              { label: "Client Info", match_types: %w[text email tel] },
              { label: "Project Details", match_types: %w[textarea select date number radio] },
              { label: "Attachments", match_types: %w[file checkbox] }
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
