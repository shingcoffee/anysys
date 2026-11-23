# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Ecommerce
      module GiftCardPurchase
        DEFINITION = {
          key: "gift_card_purchase",
          name: "Gift Card Purchase",
          description: "Digital or physical gift card order with personalized message",
          category: "ecommerce",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Gift Card Options" }],
            [{ type: :select, width: "half", label: "Card Design / Theme" }, { type: :select, width: "half", label: "Amount ($10, $25, $50, $100, $200, Custom)" }],
            [{ type: :radio, width: "full", label: "Delivery Type (Digital Email, Physical Mail)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Recipient Details" }],
            [{ type: :input, width: "half", label: "Recipient Name" }, { type: :input, width: "half", label: "Recipient Email" }],
            [{ type: :input, width: "half", label: "Recipient Phone (for physical card)" }, { type: :date, width: "half", label: "Delivery / Send Date" }],
            [{ type: :select, width: "half", label: "Occasion (Birthday, Holiday, Wedding, Thank You, Other)" }, { type: :input, width: "half", label: "Recipient Address (for physical card)" }],
            [{ type: :textarea, width: "full", label: "Personal Message" }],
            [{ type: :divider }],
            [{ type: :section, label: "Purchaser Info" }],
            [{ type: :input, width: "half", label: "Your Name" }, { type: :input, width: "half", label: "Your Email" }],
            [{ type: :input, width: "half", label: "Your Phone" }, { type: :input, width: "half", label: "Promo Code" }],
            [{ type: :checkbox, width: "full", label: "Send me a confirmation copy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Gift Card Options", match_types: %w[select radio] },
              { label: "Recipient Details", match_types: %w[text email tel date textarea] },
              { label: "Purchaser Info", match_types: %w[checkbox] }
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
