# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Library
      module CardApplication
        DEFINITION = {
          key: "library_card_application",
          name: "Library Card Application",
          description: "Library card registration with patron information, address verification, and account preferences",
          category: "library",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / Province" }],
            [{ type: :input, width: "half", label: "ZIP / Postal Code" }, { type: :select, width: "half", label: "Country" }],
            [{ type: :divider }],
            [{ type: :section, label: "Account Details" }],
            [{ type: :select, width: "half", label: "Card Type (Adult, Teen, Child, Senior, Digital Only)" }, { type: :select, width: "half", label: "Preferred Branch" }],
            [{ type: :radio, width: "full", label: "Are you a resident of the county / municipality?" }],
            [{ type: :radio, width: "full", label: "Are you a student or educator? (may qualify for extended loans)" }],
            [{ type: :select, width: "half", label: "Preferred Language" }, { type: :select, width: "half", label: "Notification Preference (Email, SMS, Phone)" }],
            [{ type: :checkbox, width: "full", label: "Areas of Interest (Fiction, Non-Fiction, Mystery, Sci-Fi, History, Children's, Science, Business, Arts, Other)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Documents & Agreement" }],
            [{ type: :file, width: "full", label: "Proof of Address (utility bill, bank statement, or government ID)" }],
            [{ type: :checkbox, width: "full", label: "I agree to the library's borrowing policies and accept responsibility for borrowed materials" }]
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
              "file" => "full"
            },
            sections: [
              { label: "Personal Information", match_types: %w[text email tel date] },
              { label: "Account & Preferences", match_types: %w[select radio checkbox] },
              { label: "Documents", match_types: %w[file] }
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
