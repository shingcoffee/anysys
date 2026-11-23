# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Registration
      module UserProfile
        DEFINITION = {
          key: "user_profile",
          name: "User Profile",
          description: "Profile editor with avatar upload, bio, and social links",
          category: "registration",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Profile Photo" }],
            [{ type: :file, width: "full", label: "Profile Photo / Avatar" }],
            [{ type: :divider }],
            [{ type: :section, label: "Basic Information" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Display Name" }, { type: :input, width: "half", label: "Username" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :select, width: "half", label: "Gender" }],
            [{ type: :select, width: "half", label: "Country" }, { type: :select, width: "half", label: "Time Zone" }],
            [{ type: :divider }],
            [{ type: :section, label: "About You" }],
            [{ type: :input, width: "half", label: "Job Title" }, { type: :input, width: "half", label: "Company / Organization" }],
            [{ type: :textarea, width: "full", label: "Bio" }],
            [{ type: :select, width: "half", label: "Preferred Language" }, { type: :select, width: "half", label: "Notification Preference" }],
            [{ type: :divider }],
            [{ type: :section, label: "Social Links" }],
            [{ type: :input, width: "half", label: "Website URL" }, { type: :input, width: "half", label: "LinkedIn Profile" }],
            [{ type: :input, width: "half", label: "Twitter / X Handle" }, { type: :input, width: "half", label: "GitHub Profile" }]
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
              "file" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Profile", match_types: %w[file] },
              { label: "Personal Info", match_types: %w[text email tel date select] },
              { label: "About & Links", match_types: %w[textarea] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
