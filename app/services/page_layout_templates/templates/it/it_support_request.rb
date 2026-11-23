# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module It
      module ItSupportRequest
        DEFINITION = {
          key: "it_support_request",
          name: "IT Support Request",
          description: "Help desk ticket with issue type, priority, and device details",
          category: "it",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Requester Info" }],
            [{ type: :input, width: "half", label: "Requester Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone / Extension" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :select, width: "half", label: "Department" }, { type: :input, width: "half", label: "Office / Location" }],
            [{ type: :divider }],
            [{ type: :section, label: "Issue Details" }],
            [{ type: :select, width: "half", label: "Issue Category (Hardware, Software, Network, Account, Email, Phone, Security, Other)" }, { type: :select, width: "half", label: "Priority (Low, Normal, High, Critical)" }],
            [{ type: :input, width: "half", label: "Device Name / Asset Tag" }, { type: :select, width: "half", label: "Operating System" }],
            [{ type: :input, width: "half", label: "Software / Application Affected" }, { type: :input, width: "half", label: "Software Version" }],
            [{ type: :input, width: "full", label: "Subject / Issue Title" }],
            [{ type: :textarea, width: "full", label: "Describe the Issue (include error messages if any)" }],
            [{ type: :textarea, width: "full", label: "Steps Already Tried" }],
            [{ type: :radio, width: "full", label: "Is this issue affecting other people?" }],
            [{ type: :date, width: "half", label: "Date Issue Started" }, { type: :select, width: "half", label: "When do you need this resolved?" }],
            [{ type: :file, width: "full", label: "Upload Screenshots, Logs, or Error Files" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Requester Info", match_types: %w[text email tel select] },
              { label: "Issue Details", match_types: %w[date radio textarea] },
              { label: "Attachments", match_types: %w[file] }
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
