# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Laundry
      module PickupRequest
        DEFINITION = {
          key: "laundry_pickup_request",
          name: "Laundry Pickup Request",
          description: "Laundry and dry cleaning pickup and delivery scheduling with garment types and special care instructions",
          category: "laundry",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Account Number (if returning customer)" }],
            [{ type: :input, width: "full", label: "Pickup Address" }],
            [{ type: :input, width: "half", label: "Delivery Address (if different)" }, { type: :select, width: "half", label: "Preferred Contact Method" }],
            [{ type: :divider }],
            [{ type: :section, label: "Service Details" }],
            [{ type: :checkbox, width: "full", label: "Services Needed (Wash & Fold, Dry Cleaning, Pressing/Ironing, Alterations, Comforter/Duvet, Shoe Cleaning)" }],
            [{ type: :number, width: "half", label: "Estimated Number of Pieces" }, { type: :select, width: "half", label: "Service Speed (Standard, Express, Same-Day)" }],
            [{ type: :date, width: "half", label: "Pickup Date" }, { type: :select, width: "half", label: "Pickup Time Window" }],
            [{ type: :date, width: "half", label: "Preferred Delivery Date" }, { type: :select, width: "half", label: "Delivery Time Window" }],
            [{ type: :divider }],
            [{ type: :section, label: "Preferences & Instructions" }],
            [{ type: :radio, width: "full", label: "Starch preference for shirts? (None, Light, Medium, Heavy)" }],
            [{ type: :radio, width: "full", label: "Hanger or folded delivery?" }],
            [{ type: :radio, width: "full", label: "Scent preference (Unscented, Fresh, Lavender, Original)" }],
            [{ type: :textarea, width: "full", label: "Special Care Instructions or Stain Notes" }],
            [{ type: :checkbox, width: "full", label: "I agree to the service terms, pricing, and liability policy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Contact & Address", match_types: %w[text email tel] },
              { label: "Service Details", match_types: %w[checkbox number select date radio] },
              { label: "Special Instructions", match_types: %w[textarea] }
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
