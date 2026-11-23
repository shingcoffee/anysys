# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Mentalhealth
      module TherapyIntake
        DEFINITION = {
          key: "therapy_intake",
          name: "Therapy Intake",
          description: "New client counseling intake with history, goals, and consent",
          category: "mentalhealth",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :input, width: "full", label: "Address" }],
            [{ type: :select, width: "half", label: "Gender" }, { type: :select, width: "half", label: "Pronouns" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Insurance & Referral" }],
            [{ type: :input, width: "half", label: "Insurance Provider" }, { type: :input, width: "half", label: "Member / Policy #" }],
            [{ type: :select, width: "half", label: "Referral Source (Self, Doctor, Employer, Insurance, Online, Other)" }, { type: :input, width: "half", label: "Referring Provider Name (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Therapy Goals & History" }],
            [{ type: :select, width: "half", label: "Primary Concern (Anxiety, Depression, Trauma, Relationships, Grief, Stress, Other)" }, { type: :select, width: "half", label: "How long have you experienced this?" }],
            [{ type: :textarea, width: "full", label: "What brings you to therapy now?" }],
            [{ type: :textarea, width: "full", label: "Previous therapy experience (if any)" }],
            [{ type: :radio, width: "full", label: "Are you currently taking any psychiatric medications?" }],
            [{ type: :textarea, width: "full", label: "Current Medications (if any)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Preferences & Consent" }],
            [{ type: :radio, width: "full", label: "Preferred session format (In-Person, Video, Phone)" }],
            [{ type: :checkbox, width: "full", label: "Available days: Mon, Tue, Wed, Thu, Fri, Sat" }],
            [{ type: :select, width: "half", label: "Preferred time of day" }, { type: :select, width: "half", label: "Session frequency (Weekly, Bi-weekly, Monthly)" }],
            [{ type: :checkbox, width: "full", label: "I consent to treatment and understand my rights" }],
            [{ type: :checkbox, width: "full", label: "I have received and acknowledge the Notice of Privacy Practices" }]
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
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Personal Details", match_types: %w[text email tel date select] },
              { label: "Therapy Goals", match_types: %w[textarea radio] },
              { label: "Preferences & Consent", match_types: %w[checkbox] }
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
