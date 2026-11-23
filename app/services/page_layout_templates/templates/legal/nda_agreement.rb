# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Legal
      module NdaAgreement
        DEFINITION = {
          key: "nda_agreement",
          name: "NDA / Agreement",
          description: "Non-disclosure agreement with parties, effective date, and signature",
          category: "legal",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Party Details" }],
            [{ type: :input, width: "half", label: "Disclosing Party Name" }, { type: :input, width: "half", label: "Disclosing Party Company" }],
            [{ type: :input, width: "half", label: "Disclosing Party Title" }, { type: :input, width: "half", label: "Disclosing Party Email" }],
            [{ type: :input, width: "half", label: "Receiving Party Name" }, { type: :input, width: "half", label: "Receiving Party Company" }],
            [{ type: :input, width: "half", label: "Receiving Party Title" }, { type: :input, width: "half", label: "Receiving Party Email" }],
            [{ type: :divider }],
            [{ type: :section, label: "Agreement Terms" }],
            [{ type: :date, width: "half", label: "Effective Date" }, { type: :select, width: "half", label: "NDA Type (One-Way / Unilateral, Mutual / Bilateral)" }],
            [{ type: :select, width: "half", label: "Duration (1 Year, 2 Years, 3 Years, 5 Years, Indefinite)" }, { type: :select, width: "half", label: "Governing Law / Jurisdiction" }],
            [{ type: :textarea, width: "full", label: "Scope of Confidential Information" }],
            [{ type: :textarea, width: "full", label: "Permitted Uses of Confidential Information" }],
            [{ type: :textarea, width: "full", label: "Exclusions from Confidentiality (if any)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Acceptance & Signature" }],
            [{ type: :checkbox, width: "full", label: "I have read, understood, and agree to all terms of this non-disclosure agreement" }],
            [{ type: :checkbox, width: "full", label: "I confirm I am authorized to enter this agreement on behalf of the stated party" }],
            [{ type: :signature, width: "full", label: "Receiving Party Signature" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "date" => "half",
              "select" => "half",
              "textarea" => "full",
              "checkbox" => "full",
            },
            sections: [
              { label: "Party Details", match_types: %w[text email date select url] },
              { label: "Agreement Terms", match_types: %w[textarea] },
              { label: "Acceptance & Signature", match_types: %w[checkbox] }
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
