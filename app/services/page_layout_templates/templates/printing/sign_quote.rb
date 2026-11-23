# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Printing
      module SignQuote
        DEFINITION = {
          key: "sign_quote",
          name: "Custom Sign Quote",
          description: "Custom signage quote request with dimensions, materials, installation requirements, and design files",
          category: "printing",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Business Name" }, { type: :input, width: "half", label: "Contact Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Installation Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Sign Specifications" }],
            [{ type: :select, width: "half", label: "Sign Type (Outdoor, Indoor, Directional, Window, Vehicle Wrap, Banner, LED, Neon, Other)" }, { type: :select, width: "half", label: "Material (Aluminum, Acrylic, PVC, Vinyl, Foam Board, Corrugated, Other)" }],
            [{ type: :input, width: "half", label: "Width (inches)" }, { type: :input, width: "half", label: "Height (inches)" }],
            [{ type: :number, width: "half", label: "Quantity" }, { type: :select, width: "half", label: "Budget Range" }],
            [{ type: :radio, width: "full", label: "Illuminated sign?" }],
            [{ type: :select, width: "half", label: "Illumination Type (if yes: Front-Lit, Back-Lit, Halo, LED)" }, { type: :select, width: "half", label: "Color Finish (Full Color, Single Color, Two Color)" }],
            [{ type: :checkbox, width: "full", label: "Mounting Options (Wall Mount, Post Mount, Window Cling, Hanging, Freestanding, Vehicle)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Design & Delivery" }],
            [{ type: :radio, width: "full", label: "Do you need installation services?" }],
            [{ type: :radio, width: "full", label: "Do you need design assistance?" }],
            [{ type: :file, width: "full", label: "Upload Logo / Design Files (AI, PDF, EPS, SVG)" }],
            [{ type: :input, width: "half", label: "Brand Colors (Hex or Pantone)" }, { type: :input, width: "half", label: "Font Preference (if known)" }],
            [{ type: :date, width: "half", label: "Needed By Date" }, { type: :select, width: "half", label: "Permit Required? (Yes, No, Unsure)" }],
            [{ type: :textarea, width: "full", label: "Additional Details or Design Notes" }],
            [{ type: :checkbox, width: "full", label: "I understand that final pricing will be confirmed after design review" }]
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
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact & Location", match_types: %w[text email tel] },
              { label: "Sign Specifications", match_types: %w[select number radio checkbox] },
              { label: "Design & Notes", match_types: %w[date textarea file] }
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
