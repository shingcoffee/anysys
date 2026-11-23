# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Laundry
      module DryCleaningDropoff
        DEFINITION = {
          key: "dry_cleaning_dropoff",
          name: "Dry Cleaning Drop-off Form",
          description: "In-store dry cleaning drop-off with garment inventory, fabric details, and stain treatment notes",
          category: "laundry",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Customer Information" }],
            [{ type: :input, width: "half", label: "Customer Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Loyalty Card / Account Number" }],
            [{ type: :divider }],
            [{ type: :section, label: "Garment Details" }],
            [{ type: :number, width: "half", label: "Total Number of Garments" }, { type: :select, width: "half", label: "Priority Level (Standard, Rush, Same-Day)" }],
            [{ type: :checkbox, width: "full", label: "Garment Types (Suit, Dress, Shirt, Pants, Coat, Wedding Gown, Tie, Bedding, Other)" }],
            [{ type: :checkbox, width: "full", label: "Special Treatments (Stain Removal, Pressing Only, Leather/Suede, Beading/Embroidery, Waterproofing)" }],
            [{ type: :select, width: "half", label: "Starch Level (None, Light, Medium, Heavy)" }, { type: :select, width: "half", label: "Hanger or Folded?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Notes & Pickup" }],
            [{ type: :textarea, width: "full", label: "Stain Locations, Fabric Concerns, or Damage Notes" }],
            [{ type: :date, width: "half", label: "Needed By Date" }, { type: :select, width: "half", label: "Preferred Pickup Time" }],
            [{ type: :radio, width: "full", label: "Preferred Pickup Notification (Phone Call, SMS, Email)" }],
            [{ type: :checkbox, width: "full", label: "I acknowledge the care policy, pricing, and liability terms" }]
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
              { label: "Customer Info", match_types: %w[text email tel] },
              { label: "Garment & Service Details", match_types: %w[number select checkbox date radio] },
              { label: "Notes & Acknowledgment", match_types: %w[textarea] }
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
