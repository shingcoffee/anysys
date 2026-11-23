# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Warranty
      module WarrantyClaim
        DEFINITION = {
          key: "warranty_claim",
          name: "Warranty Claim",
          description: "Product warranty claim with defect description, photos, and preferred resolution method",
          category: "warranty",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Customer & Product" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Order / Registration Number" }],
            [{ type: :input, width: "half", label: "Product Name / Model" }, { type: :input, width: "half", label: "Serial Number" }],
            [{ type: :date, width: "half", label: "Purchase Date" }, { type: :date, width: "half", label: "Issue First Noticed" }],
            [{ type: :input, width: "half", label: "Retailer / Store Purchased From" }, { type: :select, width: "half", label: "Warranty Type (Standard, Extended, Accidental)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Issue Details" }],
            [{ type: :select, width: "half", label: "Defect / Issue Type (Hardware, Software, Cosmetic, Functional, Other)" }, { type: :select, width: "half", label: "Severity (Minor, Moderate, Major, Inoperable)" }],
            [{ type: :radio, width: "full", label: "Has the product been repaired or modified by a third party?" }],
            [{ type: :radio, width: "full", label: "Is the issue intermittent or constant?" }],
            [{ type: :textarea, width: "full", label: "Describe the Defect or Malfunction in Detail" }],
            [{ type: :file, width: "full", label: "Upload Photos or Videos of the Issue" }],
            [{ type: :divider }],
            [{ type: :section, label: "Resolution" }],
            [{ type: :select, width: "full", label: "Preferred Resolution (Repair, Replacement, Refund, Store Credit)" }],
            [{ type: :input, width: "full", label: "Shipping Address for Replacement / Return (if applicable)" }],
            [{ type: :radio, width: "full", label: "Do you have original packaging available?" }],
            [{ type: :checkbox, width: "full", label: "I confirm the information provided is accurate and the product is within the warranty period" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "textarea" => "full",
              "file" => "full",
              "radio" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Customer & Product", match_types: %w[text email tel date] },
              { label: "Issue Details", match_types: %w[select radio textarea file] },
              { label: "Resolution", match_types: %w[checkbox] }
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
