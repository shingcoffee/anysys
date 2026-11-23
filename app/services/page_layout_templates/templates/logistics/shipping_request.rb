# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Logistics
      module ShippingRequest
        DEFINITION = {
          key: "shipping_request",
          name: "Shipping Request",
          description: "Freight or package shipping form with origin, destination, and dimensions",
          category: "logistics",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Sender Information" }],
            [{ type: :input, width: "half", label: "Sender Name" }, { type: :input, width: "half", label: "Company" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "full", label: "Pickup Address (Street, City, State, ZIP, Country)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Recipient Information" }],
            [{ type: :input, width: "half", label: "Recipient Name" }, { type: :input, width: "half", label: "Company" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "full", label: "Delivery Address (Street, City, State, ZIP, Country)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Package Details" }],
            [{ type: :number, width: "third", label: "Weight (lbs/kg)" }, { type: :number, width: "third", label: "Length (in/cm)" }, { type: :number, width: "third", label: "Width (in/cm)" }],
            [{ type: :number, width: "half", label: "Height (in/cm)" }, { type: :number, width: "half", label: "Declared Value ($)" }],
            [{ type: :select, width: "half", label: "Shipping Method (Ground, Express, Overnight, Freight)" }, { type: :date, width: "half", label: "Requested Ship Date" }],
            [{ type: :select, width: "half", label: "Service Level (Standard, Priority, Economy)" }, { type: :select, width: "half", label: "Packaging Type" }],
            [{ type: :textarea, width: "full", label: "Contents Description" }],
            [{ type: :checkbox, width: "full", label: "Special Handling: Fragile, Perishable, Hazardous Materials, Temperature Sensitive, Requires Insurance" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "third",
              "select" => "half",
              "date" => "half",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Sender & Recipient Info", match_types: %w[text email tel] },
              { label: "Package Details", match_types: %w[number select date] },
              { label: "Contents & Special Handling", match_types: %w[textarea checkbox] }
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
