# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Retail
      module CustomerLoyalty
        DEFINITION = {
          key: "customer_loyalty",
          name: "Customer Loyalty Signup",
          description: "Rewards program enrollment with preferences and communication opt-in",
          category: "retail",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :select, width: "half", label: "Gender (optional)" }],
            [{ type: :input, width: "half", label: "City" }, { type: :select, width: "half", label: "State / Province" }],
            [{ type: :divider }],
            [{ type: :section, label: "Shopping Preferences" }],
            [{ type: :select, width: "half", label: "Preferred Store Location" }, { type: :select, width: "half", label: "Shopping Frequency" }],
            [{ type: :checkbox, width: "full", label: "Favorite Shopping Categories (Clothing, Electronics, Home, Beauty, Sports, Food, Other)" }],
            [{ type: :select, width: "half", label: "How Did You Hear About Our Program?" }, { type: :select, width: "half", label: "Preferred Reward Type (Discounts, Points, Cashback, Free Shipping)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Communication & Consent" }],
            [{ type: :radio, width: "full", label: "Preferred Contact Method (Email, SMS, Phone, None)" }],
            [{ type: :checkbox, width: "full", label: "Receive personalized promotions and exclusive member offers" }],
            [{ type: :checkbox, width: "full", label: "Receive birthday and anniversary rewards" }],
            [{ type: :checkbox, width: "full", label: "I agree to the Loyalty Program Terms and Privacy Policy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "checkbox" => "full",
              "radio" => "full"
            },
            sections: [
              { label: "Your Info", match_types: %w[text email tel date] },
              { label: "Preferences", match_types: %w[checkbox select radio] },
              { label: "Communication", match_types: %w[checkbox] }
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
