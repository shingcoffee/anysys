# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module It
      module AccessPermissionRequest
        DEFINITION = {
          key: "access_permission_request",
          name: "Access Permission Request",
          description: "System access or permission change request with approval workflow",
          category: "it",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Requester Information" }],
            [{ type: :input, width: "half", label: "Requester Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :input, width: "half", label: "Email" }, { type: :select, width: "half", label: "Department" }],
            [{ type: :input, width: "half", label: "Manager Name" }, { type: :input, width: "half", label: "Manager Email" }],
            [{ type: :divider }],
            [{ type: :section, label: "Access Details" }],
            [{ type: :select, width: "half", label: "System / Application" }, { type: :radio, width: "half", label: "Request Type (New Access, Modify Access, Remove Access)" }],
            [{ type: :checkbox, width: "full", label: "Permissions Needed: Read, Write, Admin, Reporting, API Access, VPN, Remote Desktop, Database, File Share" }],
            [{ type: :select, width: "half", label: "Access Level (View Only, Standard User, Power User, Admin)" }, { type: :select, width: "half", label: "Environment (Production, Staging, Development, All)" }],
            [{ type: :date, width: "half", label: "Access Start Date" }, { type: :date, width: "half", label: "Access End Date (if temporary)" }],
            [{ type: :radio, width: "full", label: "Is this access required for a specific project?" }],
            [{ type: :input, width: "full", label: "Project Name / Business Reason (if project-based)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Justification" }],
            [{ type: :textarea, width: "full", label: "Business Justification for Access" }],
            [{ type: :checkbox, width: "full", label: "I confirm this request has been approved by the relevant manager / system owner" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Requester Info", match_types: %w[text email tel select] },
              { label: "Access Details", match_types: %w[radio checkbox date] },
              { label: "Justification", match_types: %w[textarea] }
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
