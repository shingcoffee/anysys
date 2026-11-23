# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Notary
      module AppointmentRequest
        DEFINITION = {
          key: "notary_appointment_request",
          name: "Notary Appointment Request",
          description: "Mobile or in-office notary appointment scheduling with document type, signer count, and ID requirements",
          category: "notary",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Company / Organization (optional)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Notarization Details" }],
            [{ type: :select, width: "half", label: "Document Type (Deed, Power of Attorney, Affidavit, Loan Documents, Will, Contract, Other)" }, { type: :number, width: "half", label: "Number of Documents" }],
            [{ type: :number, width: "half", label: "Number of Signers" }, { type: :select, width: "half", label: "Notary Service Type (In-Office, Mobile, Remote Online)" }],
            [{ type: :radio, width: "full", label: "Do all signers have valid government-issued photo ID?" }],
            [{ type: :radio, width: "full", label: "Is this a loan signing package?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Appointment Preferences" }],
            [{ type: :date, width: "half", label: "Preferred Date" }, { type: :select, width: "half", label: "Preferred Time" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time" }],
            [{ type: :input, width: "full", label: "Location / Address (for mobile or in-office)" }],
            [{ type: :textarea, width: "full", label: "Additional Details or Special Requirements" }],
            [{ type: :checkbox, width: "full", label: "I understand the fee schedule and agree to the notary service terms" }]
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
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Contact Information", match_types: %w[text email tel] },
              { label: "Notarization Details", match_types: %w[select number date radio] },
              { label: "Additional Info", match_types: %w[textarea checkbox] }
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
