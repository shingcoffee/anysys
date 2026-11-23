# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Optometry
      module ContactLensReorder
        DEFINITION = {
          key: "contact_lens_reorder",
          name: "Contact Lens Reorder",
          description: "Contact lens prescription reorder with lens details, prescription verification, and shipping preferences",
          category: "optometry",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Patient Information" }],
            [{ type: :input, width: "half", label: "Patient Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :divider }],
            [{ type: :section, label: "Prescription Details" }],
            [{ type: :input, width: "half", label: "Prescribing Doctor" }, { type: :date, width: "half", label: "Prescription Expiry Date" }],
            [{ type: :section, label: "Right Eye (OD)" }],
            [{ type: :input, width: "half", label: "Lens Brand / Type" }, { type: :input, width: "half", label: "Power (SPH)" }],
            [{ type: :input, width: "half", label: "CYL (Cylinder)" }, { type: :input, width: "half", label: "Axis" }],
            [{ type: :input, width: "half", label: "BC (Base Curve)" }, { type: :input, width: "half", label: "DIA (Diameter)" }],
            [{ type: :section, label: "Left Eye (OS)" }],
            [{ type: :input, width: "half", label: "Lens Brand / Type" }, { type: :input, width: "half", label: "Power (SPH)" }],
            [{ type: :input, width: "half", label: "CYL (Cylinder)" }, { type: :input, width: "half", label: "Axis" }],
            [{ type: :input, width: "half", label: "BC (Base Curve)" }, { type: :input, width: "half", label: "DIA (Diameter)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Order & Shipping" }],
            [{ type: :number, width: "half", label: "Boxes — Right Eye" }, { type: :number, width: "half", label: "Boxes — Left Eye" }],
            [{ type: :select, width: "half", label: "Shipping Method (Standard, Express, Overnight)" }, { type: :input, width: "full", label: "Shipping Address" }],
            [{ type: :select, width: "half", label: "Payment Method" }, { type: :radio, width: "half", label: "Use vision insurance?" }],
            [{ type: :file, width: "full", label: "Upload Current Prescription (optional)" }],
            [{ type: :checkbox, width: "full", label: "I confirm my prescription is valid and within expiry date" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Patient Info", match_types: %w[text email tel date] },
              { label: "Prescription & Order", match_types: %w[number select radio] },
              { label: "Documents", match_types: %w[file checkbox] }
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
