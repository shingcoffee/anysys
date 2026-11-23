# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Ecommerce
      module WholesaleOrder
        DEFINITION = {
          key: "wholesale_order",
          name: "Wholesale Order",
          description: "Bulk purchase order with product quantities and shipping details",
          category: "ecommerce",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Business Info" }],
            [{ type: :input, width: "half", label: "Company Name" }, { type: :input, width: "half", label: "Contact Person" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Tax ID / EIN" }, { type: :input, width: "half", label: "Reseller License #" }],
            [{ type: :input, width: "half", label: "Business Website" }, { type: :select, width: "half", label: "Payment Terms (Net 30, Net 60, Prepaid, COD)" }],
            [{ type: :input, width: "half", label: "Billing Address" }, { type: :select, width: "half", label: "Account Type (New, Existing)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Order Items" }],
            [{ type: :input, width: "half", label: "PO Number" }, { type: :date, width: "half", label: "Required By Date" }],
            [{ type: :select, width: "half", label: "Product 1" }, { type: :number, width: "half", label: "Quantity 1" }],
            [{ type: :select, width: "half", label: "Product 2" }, { type: :number, width: "half", label: "Quantity 2" }],
            [{ type: :select, width: "half", label: "Product 3" }, { type: :number, width: "half", label: "Quantity 3" }],
            [{ type: :number, width: "half", label: "Estimated Order Total ($)" }, { type: :select, width: "half", label: "Currency" }],
            [{ type: :textarea, width: "full", label: "Special Product Notes or Custom Requirements" }],
            [{ type: :divider }],
            [{ type: :section, label: "Shipping Details" }],
            [{ type: :input, width: "full", label: "Ship-To Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :select, width: "half", label: "Country" }, { type: :select, width: "half", label: "Shipping Method (Ground, Expedited, Freight)" }],
            [{ type: :select, width: "half", label: "Freight Terms (Prepaid, Collect, Third Party)" }, { type: :radio, width: "half", label: "Signature required on delivery?" }],
            [{ type: :textarea, width: "full", label: "Special Delivery Instructions" }],
            [{ type: :checkbox, width: "full", label: "I agree to the wholesale terms and conditions, including minimum order quantities and return policies" }]
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
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Business Info", match_types: %w[text email tel url] },
              { label: "Order Items", match_types: %w[select number date textarea] },
              { label: "Shipping Details", match_types: %w[radio checkbox] }
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
