# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Saas
      module OnboardingChecklist
        DEFINITION = {
          key: "onboarding_checklist",
          name: "Onboarding Checklist",
          description: "New user onboarding with profile setup, preferences, and guided first steps",
          category: "saas",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Profile Setup" }],
            [{ type: :input, width: "half", label: "Display Name" }, { type: :input, width: "half", label: "Job Title" }],
            [{ type: :input, width: "half", label: "Company / Organization" }, { type: :select, width: "half", label: "Team Size (1-5, 6-20, 21-50, 50+)" }],
            [{ type: :select, width: "half", label: "Department / Role (Engineering, Marketing, Sales, Operations, Design, Other)" }, { type: :select, width: "half", label: "Industry" }],
            [{ type: :file, width: "full", label: "Upload Profile Photo (optional)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Preferences" }],
            [{ type: :select, width: "half", label: "Time Zone" }, { type: :select, width: "half", label: "Preferred Language" }],
            [{ type: :select, width: "half", label: "Date Format (MM/DD/YYYY, DD/MM/YYYY)" }, { type: :select, width: "half", label: "Default Dashboard View" }],
            [{ type: :checkbox, width: "full", label: "Notification Preferences (Email Digest, In-App Alerts, Weekly Summary, Team Activity, Product Updates)" }],
            [{ type: :checkbox, width: "full", label: "Features to Enable (Integrations, API Access, Automations, Collaboration Tools, Analytics, Custom Reports)" }],
            [{ type: :radio, width: "full", label: "Would you like a guided product tour?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Goals & Use Case" }],
            [{ type: :select, width: "half", label: "Primary Use Case" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :textarea, width: "full", label: "What's your main goal with our product?" }],
            [{ type: :radio, width: "full", label: "Would you like to be assigned an onboarding specialist?" }],
            [{ type: :checkbox, width: "full", label: "I agree to the terms of service and privacy policy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "file" => "full",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Profile", match_types: %w[text email file] },
              { label: "Preferences", match_types: %w[select checkbox radio] },
              { label: "Goals", match_types: %w[textarea] }
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
