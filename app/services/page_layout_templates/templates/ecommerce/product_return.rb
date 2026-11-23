# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Ecommerce
      module ProductReturn
        DEFINITION = {
          key: "product_return",
          name: "Product Return Request",
          description: "Return or exchange request with order details and reason",
          category: "ecommerce",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Order Information" }],
            [{ type: :input, width: "half", label: "Order Number" }, { type: :date, width: "half", label: "Purchase Date" }],
            [{ type: :input, width: "half", label: "Customer Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :select, width: "half", label: "Purchase Channel (Website, Store, App, Phone)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Return Details" }],
            [{ type: :input, width: "half", label: "Product Name" }, { type: :input, width: "half", label: "SKU / Item Number" }],
            [{ type: :number, width: "half", label: "Quantity to Return" }, { type: :select, width: "half", label: "Item Condition (New/Unopened, Like New, Used, Damaged)" }],
            [{ type: :select, width: "half", label: "Return Reason (Defective, Wrong Item, Not as Described, Changed Mind, Arrived Damaged, Other)" }, { type: :select, width: "half", label: "Request Type (Return Refund, Exchange, Store Credit)" }],
            [{ type: :textarea, width: "full", label: "Additional Details or Description of Issue" }],
            [{ type: :file, width: "full", label: "Upload Photos of Item (if damaged or defective)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Refund Preference" }],
            [{ type: :radio, width: "full", label: "Preferred Refund Method (Original Payment Method, Store Credit, Exchange)" }],
            [{ type: :input, width: "full", label: "Exchange Item (if requesting exchange — name, size, color)" }],
            [{ type: :input, width: "full", label: "Return Shipping Address (if mailing item back)" }],
            [{ type: :checkbox, width: "full", label: "I confirm the item is in its original packaging with all accessories and tags included" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Order Information", match_types: %w[text email tel number date select] },
              { label: "Return Details", match_types: %w[textarea file] },
              { label: "Refund Preference", match_types: %w[radio checkbox] }
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
