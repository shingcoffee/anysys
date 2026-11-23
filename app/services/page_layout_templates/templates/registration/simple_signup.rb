# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Registration
      module SimpleSignup
        DEFINITION = {
          key: "simple_signup",
          name: "Simple Sign-Up",
          description: "Minimal registration — name, email, and password",
          category: "registration",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Create Your Account" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "full", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Password" }, { type: :input, width: "half", label: "Confirm Password" }],
            [{ type: :input, width: "half", label: "Phone Number (optional)" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Consent" }],
            [{ type: :checkbox, width: "full", label: "I agree to the Terms of Service and Privacy Policy" }],
            [{ type: :checkbox, width: "full", label: "Send me product updates and newsletters (optional)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "full",
              "tel" => "half",
              "select" => "half",
              "checkbox" => "full",
              "password" => "half",
            },
            sections: [
              { label: "Account Details", match_types: %w[text email tel select password] },
              { label: "Consent", match_types: %w[checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
