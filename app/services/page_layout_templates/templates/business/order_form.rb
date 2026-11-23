# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Business
      module OrderForm
        DEFINITION = {
          key: "order_form",
          name: "Order Form",
          description: "Purchase order with quantities, shipping, and payment details",
          category: "business",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Customer Information" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Company Name (if applicable)" }, { type: :input, width: "half", label: "Customer Account #" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :divider }],
            [{ type: :section, label: "Order Details" }],
            [{ type: :input, width: "half", label: "Product Name / SKU (Item 1)" }, { type: :number, width: "half", label: "Quantity" }],
            [{ type: :number, width: "half", label: "Unit Price ($)" }, { type: :number, width: "half", label: "Line Total ($)" }],
            [{ type: :input, width: "half", label: "Product Name / SKU (Item 2)" }, { type: :number, width: "half", label: "Quantity" }],
            [{ type: :number, width: "half", label: "Unit Price ($)" }, { type: :number, width: "half", label: "Line Total ($)" }],
            [{ type: :input, width: "half", label: "Product Name / SKU (Item 3)" }, { type: :number, width: "half", label: "Quantity" }],
            [{ type: :number, width: "half", label: "Unit Price ($)" }, { type: :number, width: "half", label: "Line Total ($)" }],
            [{ type: :number, width: "half", label: "Subtotal ($)" }, { type: :number, width: "half", label: "Shipping & Handling ($)" }],
            [{ type: :number, width: "half", label: "Tax ($)" }, { type: :number, width: "half", label: "Total Amount ($)" }],
            [{ type: :select, width: "full", label: "Payment Method (Credit Card, PayPal, Purchase Order, Wire Transfer, Check)" }],
            [{ type: :input, width: "half", label: "Purchase Order Number (if applicable)" }, { type: :input, width: "half", label: "Promo / Coupon Code" }],
            [{ type: :divider }],
            [{ type: :section, label: "Shipping & Notes" }],
            [{ type: :input, width: "full", label: "Shipping Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :select, width: "half", label: "Country" }, { type: :select, width: "half", label: "Shipping Method (Standard, Expedited, Overnight)" }],
            [{ type: :date, width: "half", label: "Requested Delivery Date" }, { type: :radio, width: "half", label: "Billing Address Same as Shipping?" }],
            [{ type: :textarea, width: "full", label: "Special Instructions or Delivery Notes" }],
            [{ type: :checkbox, width: "full", label: "I agree to the terms of sale and return policy" }]
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
              { label: "Customer Information", match_types: %w[text email tel url] },
              { label: "Order Details", match_types: %w[select number] },
              { label: "Shipping & Notes", match_types: %w[date radio textarea checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
