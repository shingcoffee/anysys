# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Ecommerce
      module CustomerReview
        DEFINITION = {
          key: "customer_review",
          name: "Customer Review",
          description: "Product review form with star ratings, photos, and pros/cons",
          category: "ecommerce",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Reviewer Info" }],
            [{ type: :input, width: "half", label: "Your Name (or Display Name)" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "full", label: "Product Name" }],
            [{ type: :input, width: "half", label: "Order Number (optional)" }, { type: :date, width: "half", label: "Purchase Date" }],
            [{ type: :select, width: "half", label: "How long have you owned / used this product?" }, { type: :select, width: "half", label: "Purchase Channel (Website, Store, App)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Ratings" }],
            [{ type: :select, width: "half", label: "Overall Rating (1-Poor to 5-Excellent)" }, { type: :select, width: "half", label: "Quality Rating (1-5)" }],
            [{ type: :select, width: "half", label: "Value for Money (1-5)" }, { type: :select, width: "half", label: "Ease of Use (1-5)" }],
            [{ type: :select, width: "half", label: "Would You Buy Again? (Definitely, Maybe, No)" }, { type: :radio, width: "half", label: "Verified Purchase?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Review" }],
            [{ type: :input, width: "full", label: "Review Title / Headline" }],
            [{ type: :textarea, width: "full", label: "Your Full Review" }],
            [{ type: :input, width: "half", label: "What did you like most? (Pros)" }, { type: :input, width: "half", label: "What could be improved? (Cons)" }],
            [{ type: :file, width: "full", label: "Upload Photos or Videos of the Product" }],
            [{ type: :checkbox, width: "full", label: "I recommend this product to others" }],
            [{ type: :checkbox, width: "full", label: "I certify this review is based on my genuine experience with this product" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Reviewer Info", match_types: %w[text email date select] },
              { label: "Ratings", match_types: %w[radio range] },
              { label: "Your Review", match_types: %w[textarea checkbox file] }
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
