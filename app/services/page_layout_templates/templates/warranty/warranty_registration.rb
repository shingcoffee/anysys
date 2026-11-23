# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Warranty
      module WarrantyRegistration
        DEFINITION = {
          key: "warranty_registration",
          name: "Warranty Registration",
          description: "Product warranty registration with purchase details, serial number, and proof of purchase upload",
          category: "warranty",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Owner Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "full", label: "Mailing Address" }],
            [{ type: :select, width: "half", label: "Country" }, { type: :select, width: "half", label: "Preferred Contact Method (Email, Phone)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Product & Purchase" }],
            [{ type: :select, width: "half", label: "Product Category" }, { type: :input, width: "half", label: "Product Name / Model Number" }],
            [{ type: :input, width: "half", label: "Serial Number" }, { type: :date, width: "half", label: "Purchase Date" }],
            [{ type: :input, width: "half", label: "Retailer / Store Name" }, { type: :select, width: "half", label: "Purchase Channel (In-Store, Online, Authorized Dealer, Other)" }],
            [{ type: :select, width: "half", label: "Warranty Plan (Standard, Extended, Accidental)" }, { type: :input, width: "half", label: "Purchase Price (optional)" }],
            [{ type: :radio, width: "full", label: "Was this product purchased as a gift?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Upload & Agreement" }],
            [{ type: :file, width: "full", label: "Upload Proof of Purchase (receipt, invoice, or order confirmation)" }],
            [{ type: :radio, width: "full", label: "Would you like information about extended warranty options?" }],
            [{ type: :radio, width: "full", label: "May we contact you with product updates and support tips?" }],
            [{ type: :checkbox, width: "full", label: "I agree to the warranty terms and conditions" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "file" => "full",
              "radio" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Owner Info", match_types: %w[text email tel] },
              { label: "Product & Purchase", match_types: %w[select date radio] },
              { label: "Upload & Agreement", match_types: %w[file checkbox] }
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
