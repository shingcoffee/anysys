# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Payment
      module SubscriptionForm
        DEFINITION = {
          key: "subscription_form",
          name: "Subscription / Membership",
          description: "Recurring subscription with plan selection and billing cycle",
          category: "payment",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Choose Your Plan" }],
            [{ type: :radio, width: "full", label: "Plan Tier (Basic, Pro, Business, Enterprise)" }],
            [{ type: :select, width: "half", label: "Billing Cycle (Monthly, Annual)" }, { type: :number, width: "half", label: "Number of Seats / Users" }],
            [{ type: :select, width: "half", label: "Add-ons" }, { type: :select, width: "half", label: "Promo / Coupon Code" }],
            [{ type: :divider }],
            [{ type: :section, label: "Account Details" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "half", label: "Company" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :input, width: "full", label: "Billing Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Payment & Agreement" }],
            [{ type: :select, width: "half", label: "Payment Method (Credit Card, PayPal, Bank Transfer)" }, { type: :select, width: "half", label: "Currency" }],
            [{ type: :radio, width: "full", label: "Do you need an invoice for your company?" }],
            [{ type: :checkbox, width: "full", label: "I agree to the subscription terms, billing policy, and privacy policy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Plan Selection", match_types: %w[radio select number range] },
              { label: "Account Details", match_types: %w[text email tel url] },
              { label: "Payment & Terms", match_types: %w[checkbox] }
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
