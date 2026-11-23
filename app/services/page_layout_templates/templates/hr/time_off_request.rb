# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hr
      module TimeOffRequest
        DEFINITION = {
          key: "time_off_request",
          name: "Time Off Request",
          description: "Employee leave request with date range, type, and manager approval",
          category: "hr",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Employee Details" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :input, width: "half", label: "Email" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :select, width: "half", label: "Department" }, { type: :input, width: "half", label: "Manager Name" }],
            [{ type: :divider }],
            [{ type: :section, label: "Leave Details" }],
            [{ type: :select, width: "half", label: "Leave Type (Vacation, Sick, Personal, Parental, Bereavement, Unpaid, FMLA, Other)" }, { type: :select, width: "half", label: "Leave Duration" }],
            [{ type: :date, width: "half", label: "Start Date" }, { type: :date, width: "half", label: "Return Date" }],
            [{ type: :number, width: "half", label: "Total Days Requested" }, { type: :radio, width: "half", label: "Full Day or Half Day?" }],
            [{ type: :textarea, width: "full", label: "Reason for Leave" }],
            [{ type: :divider }],
            [{ type: :section, label: "Coverage & Approval" }],
            [{ type: :input, width: "half", label: "Coverage Person (who will cover your duties)" }, { type: :input, width: "half", label: "Coverage Contact" }],
            [{ type: :radio, width: "full", label: "Is coverage arranged?" }],
            [{ type: :textarea, width: "full", label: "Handover Notes / Work in Progress" }],
            [{ type: :checkbox, width: "full", label: "I confirm I have sufficient leave balance for this request" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "number" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Employee Details", match_types: %w[text email tel select] },
              { label: "Leave Details", match_types: %w[date number radio textarea] },
              { label: "Coverage & Approval", match_types: %w[checkbox] }
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
