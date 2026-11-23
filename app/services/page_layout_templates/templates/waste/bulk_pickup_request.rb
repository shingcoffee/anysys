# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Waste
      module BulkPickupRequest
        DEFINITION = {
          key: "bulk_pickup_request",
          name: "Bulk Pickup Request",
          description: "Large item or bulk waste pickup scheduling with item list, location, and access details",
          category: "waste",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact & Address" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Account Number (if any)" }],
            [{ type: :input, width: "full", label: "Pickup Address" }],
            [{ type: :select, width: "half", label: "Property Type (Residential, Commercial, Multi-Family)" }, { type: :select, width: "half", label: "Pickup Location on Property (Curb, Driveway, Backyard, Alley)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Items & Scheduling" }],
            [{ type: :checkbox, width: "full", label: "Items for Pickup (Furniture, Appliances, Electronics, Mattress, Yard Waste, Construction Debris, Tires, Boxes, Other)" }],
            [{ type: :number, width: "half", label: "Estimated Number of Items" }, { type: :select, width: "half", label: "Largest Item (Fits in Car Trunk, Fits in Van, Requires Truck)" }],
            [{ type: :radio, width: "full", label: "Do any items contain hazardous materials (paint, chemicals, batteries)?" }],
            [{ type: :date, width: "half", label: "Preferred Pickup Date" }, { type: :select, width: "half", label: "Preferred Time Window" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time Window" }],
            [{ type: :divider }],
            [{ type: :section, label: "Details & Photos" }],
            [{ type: :textarea, width: "full", label: "Item Descriptions and Any Special Notes" }],
            [{ type: :radio, width: "full", label: "Is gate or access code required to enter property?" }],
            [{ type: :input, width: "full", label: "Access Code or Gate Instructions (if yes)" }],
            [{ type: :file, width: "full", label: "Upload Photos of Items (optional)" }],
            [{ type: :checkbox, width: "full", label: "I confirm the items are accessible and ready for pickup on the requested date" }]
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
              { label: "Contact & Address", match_types: %w[text email tel] },
              { label: "Items & Scheduling", match_types: %w[checkbox number select date radio] },
              { label: "Details & Photos", match_types: %w[textarea file] }
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
