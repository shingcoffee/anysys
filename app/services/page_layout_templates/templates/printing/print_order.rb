# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Printing
      module PrintOrder
        DEFINITION = {
          key: "print_order",
          name: "Print Order Request",
          description: "Custom printing order with product type, quantity, paper stock, finishing options, and file upload",
          category: "printing",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Contact Name" }, { type: :input, width: "half", label: "Company / Organization" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Billing Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Print Specifications" }],
            [{ type: :select, width: "half", label: "Product Type (Business Cards, Flyers, Brochures, Banners, Posters, Booklets, Other)" }, { type: :number, width: "half", label: "Quantity" }],
            [{ type: :select, width: "half", label: "Paper Size (Letter, Legal, A4, 4x6, 5x7, Custom)" }, { type: :select, width: "half", label: "Paper Stock (Standard, Glossy, Matte, Cardstock, Recycled)" }],
            [{ type: :select, width: "half", label: "Color Option (Full Color, Black & White, Spot Color)" }, { type: :select, width: "half", label: "Print Sides (Single, Double)" }],
            [{ type: :select, width: "half", label: "Print Quantity (25, 50, 100, 250, 500, 1000, Custom)" }, { type: :select, width: "half", label: "Turnaround (Standard 5-7 Days, Rush 2-3 Days, Same Day)" }],
            [{ type: :checkbox, width: "full", label: "Finishing Options (Lamination, UV Coating, Rounded Corners, Folding, Stapling, Binding, Die Cut)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Artwork & Delivery" }],
            [{ type: :file, width: "full", label: "Upload Artwork / Design Files (PDF, AI, PSD, EPS)" }],
            [{ type: :radio, width: "full", label: "Do you need design assistance?" }],
            [{ type: :select, width: "half", label: "Design Template Preference (if applicable)" }, { type: :input, width: "half", label: "Brand Color Codes (if applicable)" }],
            [{ type: :date, width: "half", label: "Needed By Date" }, { type: :select, width: "half", label: "Delivery Method (Pickup, Standard Shipping, Express Shipping)" }],
            [{ type: :input, width: "full", label: "Shipping Address (if different from billing)" }],
            [{ type: :textarea, width: "full", label: "Special Instructions or Notes" }],
            [{ type: :checkbox, width: "full", label: "I confirm that the uploaded files are print-ready and I approve the order specifications" }]
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
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact Information", match_types: %w[text email tel] },
              { label: "Print Specifications", match_types: %w[select number checkbox] },
              { label: "Artwork & Instructions", match_types: %w[date radio textarea file] }
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
