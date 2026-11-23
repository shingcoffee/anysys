# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Research
      module ResearchConsent
        DEFINITION = {
          key: "research_consent",
          name: "Research Consent",
          description: "Informed consent for research participation with study details and signature",
          category: "research",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Participant Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Mailing Address" }],
            [{ type: :select, width: "half", label: "Gender" }, { type: :select, width: "half", label: "Ethnicity (optional)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Study Information" }],
            [{ type: :input, width: "full", label: "Study Title" }],
            [{ type: :input, width: "half", label: "Principal Investigator" }, { type: :input, width: "half", label: "Institution / Organization" }],
            [{ type: :input, width: "half", label: "IRB Protocol Number" }, { type: :input, width: "half", label: "Study Contact Email" }],
            [{ type: :textarea, width: "full", label: "Study Purpose & Procedures" }],
            [{ type: :textarea, width: "full", label: "Potential Risks & Discomforts" }],
            [{ type: :textarea, width: "full", label: "Potential Benefits" }],
            [{ type: :select, width: "half", label: "Study Duration" }, { type: :select, width: "half", label: "Compensation (if any)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Consent & Authorization" }],
            [{ type: :radio, width: "full", label: "Are you 18 years of age or older?" }],
            [{ type: :checkbox, width: "full", label: "I have read and understand the study information above" }],
            [{ type: :checkbox, width: "full", label: "I consent to participate voluntarily and may withdraw at any time" }],
            [{ type: :checkbox, width: "full", label: "I consent to audio/video recording (if applicable)" }],
            [{ type: :checkbox, width: "full", label: "I consent to data being used in publications and presentations" }],
            [{ type: :date, width: "half", label: "Date of Consent" }, { type: :signature, width: "half", label: "Participant Signature" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "textarea" => "full",
              "checkbox" => "full",
              "radio" => "full",
            },
            sections: [
              { label: "Participant Details", match_types: %w[text email tel date select] },
              { label: "Study Details", match_types: %w[textarea] },
              { label: "Consent & Signature", match_types: %w[checkbox radio] }
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
