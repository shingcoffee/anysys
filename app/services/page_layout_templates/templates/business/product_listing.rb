# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Business
      module ProductListing
        DEFINITION = {
          key: "product_listing",
          name: "Product Listing",
          description: "E-commerce product form with pricing, variants, and media",
          category: "business",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Product Details" }],
            [{ type: :input, width: "full", label: "Product Name" }],
            [{ type: :input, width: "half", label: "Brand / Manufacturer" }, { type: :select, width: "half", label: "Product Category" }],
            [{ type: :textarea, width: "full", label: "Short Description (for listing preview)" }],
            [{ type: :textarea, width: "full", label: "Full Product Description" }],
            [{ type: :divider }],
            [{ type: :section, label: "Pricing & Inventory" }],
            [{ type: :number, width: "half", label: "Regular Price ($)" }, { type: :number, width: "half", label: "Sale Price ($, if applicable)" }],
            [{ type: :number, width: "half", label: "Cost of Goods ($)" }, { type: :number, width: "half", label: "Stock Quantity" }],
            [{ type: :input, width: "half", label: "SKU / Product Code" }, { type: :input, width: "half", label: "Barcode / UPC / EAN" }],
            [{ type: :select, width: "half", label: "Stock Status (In Stock, Out of Stock, Pre-Order, Backorder)" }, { type: :number, width: "half", label: "Low Stock Threshold" }],
            [{ type: :select, width: "half", label: "Tax Class (Standard, Reduced, Zero)" }, { type: :select, width: "half", label: "Currency" }],
            [{ type: :divider }],
            [{ type: :section, label: "Options & Media" }],
            [{ type: :input, width: "half", label: "Color / Finish Options (comma-separated)" }, { type: :input, width: "half", label: "Size Options (e.g., S, M, L, XL)" }],
            [{ type: :input, width: "half", label: "Weight (lbs / kg)" }, { type: :input, width: "half", label: "Dimensions (L x W x H)" }],
            [{ type: :select, width: "half", label: "Shipping Category (Standard, Oversized, Fragile, Digital)" }, { type: :radio, width: "half", label: "Requires special handling?" }],
            [{ type: :checkbox, width: "full", label: "Product Tags / Attributes (New Arrival, Bestseller, Sale, Eco-Friendly, Handmade, Limited Edition)" }],
            [{ type: :file, width: "full", label: "Upload Product Images (JPG, PNG — Main image first)" }],
            [{ type: :textarea, width: "full", label: "Internal Notes (not visible to customers)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "number" => "half",
              "select" => "half",
              "text" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "file" => "full",
              "textarea" => "full",
              "color" => "third",
            },
            sections: [
              { label: "Product Details", match_types: %w[text textarea] },
              { label: "Pricing & Inventory", match_types: %w[number select range] },
              { label: "Options & Media", match_types: %w[radio checkbox file color] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
