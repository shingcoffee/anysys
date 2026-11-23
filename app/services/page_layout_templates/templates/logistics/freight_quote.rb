# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Logistics
      module FreightQuote
        DEFINITION = {
          key: "freight_quote",
          name: "Freight Quote",
          description: "Freight shipping quote with origin, destination, cargo details, and special handling",
          category: "logistics",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Company Name" }, { type: :input, width: "half", label: "Contact Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :select, width: "half", label: "Account Type (New Customer, Existing, Broker)" }, { type: :input, width: "half", label: "Account / Customer ID (if existing)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Shipment Details" }],
            [{ type: :input, width: "full", label: "Origin Address (City, State, Country, ZIP)" }],
            [{ type: :input, width: "full", label: "Destination Address (City, State, Country, ZIP)" }],
            [{ type: :date, width: "half", label: "Ready to Ship Date" }, { type: :select, width: "half", label: "Service Type (LTL, FTL, Expedited, Ocean, Air)" }],
            [{ type: :select, width: "half", label: "Transit Priority (Standard, Expedited, Economy)" }, { type: :select, width: "half", label: "Incoterms (EXW, FOB, CIF, DDP, Other)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Cargo Details" }],
            [{ type: :number, width: "third", label: "Total Weight (kg/lbs)" }, { type: :number, width: "third", label: "Number of Pieces" }, { type: :select, width: "third", label: "Packaging Type" }],
            [{ type: :input, width: "half", label: "Dimensions per Unit (L x W x H)" }, { type: :select, width: "half", label: "Commodity / Freight Class" }],
            [{ type: :number, width: "half", label: "Declared Value ($)" }, { type: :select, width: "half", label: "Currency" }],
            [{ type: :checkbox, width: "full", label: "Special Requirements (Hazmat, Temperature Control, Fragile, Oversized, Liftgate, Inside Delivery)" }],
            [{ type: :textarea, width: "full", label: "Additional Notes or Instructions" }],
            [{ type: :checkbox, width: "full", label: "I confirm the cargo details are accurate and compliant with regulations" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "third",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Shipment & Cargo", match_types: %w[date select number] },
              { label: "Requirements & Notes", match_types: %w[checkbox textarea] }
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
