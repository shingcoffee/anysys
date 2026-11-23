# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Payment
      module PaymentRequest
        DEFINITION = {
          key: "payment_request",
          name: "Payment Request",
          description: "Collect payments with billing address and payment method selection",
          category: "payment",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Billing Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :input, width: "half", label: "Company (Optional)" }],
            [{ type: :input, width: "full", label: "Billing Address" }],
            [{ type: :input, width: "third", label: "City" }, { type: :input, width: "third", label: "State / Province" }, { type: :input, width: "third", label: "ZIP / Postal Code" }],
            [{ type: :select, width: "half", label: "Country" }, { type: :input, width: "half", label: "VAT / Tax ID (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Payment Details" }],
            [{ type: :input, width: "half", label: "Invoice / Reference Number" }, { type: :number, width: "half", label: "Amount ($)" }],
            [{ type: :select, width: "half", label: "Payment Method (Credit Card, Bank Transfer, PayPal, Check, Other)" }, { type: :select, width: "half", label: "Currency" }],
            [{ type: :textarea, width: "full", label: "Payment Description / Notes" }],
            [{ type: :checkbox, width: "full", label: "I authorize this payment and agree to the terms" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Billing Info", match_types: %w[text email tel select] },
              { label: "Payment Details", match_types: %w[number textarea] },
              { label: "Authorization", match_types: %w[checkbox] }
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
