# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Compliance
      module AuditChecklist
        DEFINITION = {
          key: "audit_checklist",
          name: "Audit Checklist",
          description: "Internal or external audit checklist with control areas, evidence collection, and findings",
          category: "compliance",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Audit Information" }],
            [{ type: :input, width: "half", label: "Auditor Name" }, { type: :input, width: "half", label: "Department / Area Audited" }],
            [{ type: :date, width: "half", label: "Audit Date" }, { type: :select, width: "half", label: "Audit Type (Internal, External, Regulatory, ISO, Financial)" }],
            [{ type: :input, width: "half", label: "Audit Reference #" }, { type: :select, width: "half", label: "Audit Scope (Full, Partial, Follow-Up)" }],
            [{ type: :input, width: "half", label: "Auditee Name / Contact" }, { type: :input, width: "half", label: "Auditee Title" }],
            [{ type: :divider }],
            [{ type: :section, label: "Control Assessment" }],
            [{ type: :select, width: "half", label: "Control Category (Access, Financial, Operational, IT, HR)" }, { type: :select, width: "half", label: "Risk Level (Low, Medium, High, Critical)" }],
            [{ type: :radio, width: "full", label: "Is the control documented and current?" }],
            [{ type: :radio, width: "full", label: "Is the control being followed as documented?" }],
            [{ type: :select, width: "half", label: "Compliance Rating (Compliant, Partially Compliant, Non-Compliant)" }, { type: :select, width: "half", label: "Test Result (Pass, Fail, Inconclusive)" }],
            [{ type: :number, width: "half", label: "Number of Exceptions Found" }, { type: :select, width: "half", label: "Overall Control Effectiveness (1-5)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Findings & Evidence" }],
            [{ type: :textarea, width: "full", label: "Observations & Notes" }],
            [{ type: :textarea, width: "full", label: "Non-Conformities / Deficiencies Identified" }],
            [{ type: :textarea, width: "full", label: "Recommended Corrective Actions" }],
            [{ type: :select, width: "half", label: "Priority (Low, Medium, High, Critical)" }, { type: :date, width: "half", label: "Corrective Action Due Date" }],
            [{ type: :input, width: "half", label: "Assigned To (Responsible Party)" }, { type: :date, width: "half", label: "Follow-Up Review Date" }],
            [{ type: :file, width: "full", label: "Upload Evidence Documents, Screenshots, or Supporting Files" }],
            [{ type: :signature, width: "full", label: "Auditor Signature" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
            },
            sections: [
              { label: "Audit Info", match_types: %w[text email date] },
              { label: "Control Assessment", match_types: %w[select number radio] },
              { label: "Findings & Evidence", match_types: %w[textarea checkbox file] }
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
