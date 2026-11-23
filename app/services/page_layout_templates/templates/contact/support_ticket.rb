# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Contact
      module SupportTicket
        DEFINITION = {
          key: "support_ticket",
          name: "Support Ticket",
          description: "Help desk form with priority, category, and file attachments",
          category: "contact",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Submitter Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Account / Customer ID" }],
            [{ type: :input, width: "half", label: "Company / Organization" }, { type: :select, width: "half", label: "Preferred Contact Method (Email, Phone)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Ticket Details" }],
            [{ type: :input, width: "full", label: "Subject / Issue Summary" }],
            [{ type: :select, width: "half", label: "Category (Technical, Billing, Account, Feature Request, Other)" }, { type: :select, width: "half", label: "Priority (Low, Normal, High, Critical)" }],
            [{ type: :input, width: "half", label: "Product / Service Name" }, { type: :input, width: "half", label: "Version / Plan" }],
            [{ type: :select, width: "half", label: "Impact (Single User, Team, All Users)" }, { type: :date, width: "half", label: "Date Issue First Occurred" }],
            [{ type: :divider }],
            [{ type: :section, label: "Issue Description" }],
            [{ type: :textarea, width: "full", label: "Describe the Issue in Detail" }],
            [{ type: :textarea, width: "full", label: "Steps to Reproduce (if applicable)" }],
            [{ type: :textarea, width: "full", label: "Expected Behavior vs. Actual Behavior" }],
            [{ type: :input, width: "half", label: "Browser / App Version" }, { type: :input, width: "half", label: "Operating System" }],
            [{ type: :radio, width: "full", label: "Have you tried restarting or reinstalling?" }],
            [{ type: :file, width: "full", label: "Upload Screenshots or Attachments" }]
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
              { label: "Submitter Info", match_types: %w[text email tel] },
              { label: "Ticket Details", match_types: %w[select date] },
              { label: "Issue Description", match_types: %w[textarea radio file] }
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
