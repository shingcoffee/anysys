# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Waste
      module RecyclingSchedule
        DEFINITION = {
          key: "recycling_schedule",
          name: "Recycling Schedule Request",
          description: "Residential recycling bin request and collection schedule with material types and address verification",
          category: "waste",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Resident Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Account Number (if any)" }],
            [{ type: :input, width: "full", label: "Service Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "ZIP / Postal Code" }],
            [{ type: :select, width: "half", label: "Property Type (Single Family, Apartment, Condo, Townhouse, Business)" }, { type: :select, width: "half", label: "Number of Units (if multi-family)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Recycling Services" }],
            [{ type: :select, width: "half", label: "Request Type (New Service, Change Schedule, Add Bin, Replace Bin, Report Issue)" }, { type: :select, width: "half", label: "Bin Size (32 gal, 64 gal, 96 gal)" }],
            [{ type: :checkbox, width: "full", label: "Recyclable Materials (Paper/Cardboard, Plastic Bottles, Glass, Aluminum Cans, Tin, Electronics, Organic/Compost)" }],
            [{ type: :select, width: "half", label: "Preferred Collection Day (Mon–Fri)" }, { type: :select, width: "half", label: "Current Collection Day (if any)" }],
            [{ type: :radio, width: "full", label: "Do you have items that exceed bin capacity (e.g. flattened cardboard bundles)?" }],
            [{ type: :radio, width: "full", label: "Do you need a replacement or additional bin?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Additional Details" }],
            [{ type: :textarea, width: "full", label: "Special Instructions or Concerns" }],
            [{ type: :checkbox, width: "full", label: "I confirm this is my residential or commercial service address" }]
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
              { label: "Resident Information", match_types: %w[text email tel] },
              { label: "Recycling Services", match_types: %w[select checkbox radio] },
              { label: "Additional Details", match_types: %w[textarea] }
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
