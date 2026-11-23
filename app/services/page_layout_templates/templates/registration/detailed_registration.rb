# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Registration
      module DetailedRegistration
        DEFINITION = {
          key: "detailed_registration",
          name: "Detailed Registration",
          description: "Full registration with personal info, address, and preferences",
          category: "registration",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :select, width: "half", label: "Gender" }],
            [{ type: :input, width: "half", label: "Username" }, { type: :input, width: "half", label: "Password" }],
            [{ type: :divider }],
            [{ type: :section, label: "Address" }],
            [{ type: :input, width: "full", label: "Street Address" }],
            [{ type: :input, width: "half", label: "Apartment / Suite (optional)" }, { type: :input, width: "half", label: "City" }],
            [{ type: :input, width: "half", label: "State / Province" }, { type: :input, width: "half", label: "ZIP / Postal Code" }],
            [{ type: :select, width: "half", label: "Country" }, { type: :select, width: "half", label: "Time Zone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Profile & Preferences" }],
            [{ type: :select, width: "half", label: "Account Type" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :select, width: "half", label: "Preferred Language" }, { type: :select, width: "half", label: "Preferred Communication Channel" }],
            [{ type: :textarea, width: "full", label: "Bio / About You (optional)" }],
            [{ type: :checkbox, width: "full", label: "Subscribe to newsletter and product updates" }],
            [{ type: :checkbox, width: "full", label: "I agree to the Terms of Service and Privacy Policy" }]
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
              "password" => "half",
              "url" => "half",
            },
            sections: [
              { label: "Personal Information", match_types: %w[text email tel date password] },
              { label: "Contact & Address", match_types: %w[select url] },
              { label: "Preferences & Consent", match_types: %w[textarea checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
