# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Notary
      module DocumentCertification
        DEFINITION = {
          key: "notary_document_certification",
          name: "Document Certification Request",
          description: "Certified copy and document authentication request with document details, purpose, and submission",
          category: "notary",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Requester Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Organization / Institution (optional)" }],
            [{ type: :input, width: "full", label: "Mailing / Delivery Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Document Information" }],
            [{ type: :select, width: "half", label: "Document Type (Birth Certificate, Diploma, Passport, Contract, Power of Attorney, Other)" }, { type: :select, width: "half", label: "Certification Type (Notarized Copy, Apostille, Authentication, Legalization)" }],
            [{ type: :number, width: "half", label: "Number of Certified Copies" }, { type: :select, width: "half", label: "Destination Country (if international)" }],
            [{ type: :radio, width: "full", label: "Is an Apostille required?" }],
            [{ type: :radio, width: "full", label: "Is translation required?" }],
            [{ type: :textarea, width: "full", label: "Purpose of Certification" }],
            [{ type: :divider }],
            [{ type: :section, label: "Submission & Delivery" }],
            [{ type: :file, width: "full", label: "Upload Document(s) for Certification" }],
            [{ type: :select, width: "half", label: "Turnaround Time (Standard, Rush, Same-Day)" }, { type: :select, width: "half", label: "Delivery Method (Pickup, Mail, Email PDF, Courier)" }],
            [{ type: :textarea, width: "full", label: "Special Instructions" }],
            [{ type: :checkbox, width: "full", label: "I confirm the documents are authentic and I agree to the service terms and fees" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Requester Info", match_types: %w[text email tel] },
              { label: "Document & Certification Details", match_types: %w[select number radio] },
              { label: "Documents & Notes", match_types: %w[textarea file checkbox] }
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
