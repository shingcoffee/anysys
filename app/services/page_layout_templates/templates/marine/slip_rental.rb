# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Marine
      module SlipRental
        DEFINITION = {
          key: "marina_slip_rental",
          name: "Marina Slip Rental Application",
          description: "Marina boat slip rental application with vessel dimensions, insurance, and lease term preferences",
          category: "marine",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Owner Information" }],
            [{ type: :input, width: "half", label: "Owner Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "full", label: "Mailing Address" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Vessel Details" }],
            [{ type: :input, width: "half", label: "Boat Name" }, { type: :input, width: "half", label: "State Registration Number" }],
            [{ type: :select, width: "half", label: "Vessel Type (Powerboat, Sailboat, Pontoon, Catamaran, PWC)" }, { type: :number, width: "half", label: "Year Built" }],
            [{ type: :input, width: "half", label: "Length Overall (feet)" }, { type: :input, width: "half", label: "Beam (feet)" }],
            [{ type: :input, width: "half", label: "Draft (feet)" }, { type: :select, width: "half", label: "Power Type (Inboard, Outboard, Sail, Electric)" }],
            [{ type: :input, width: "half", label: "Vessel Make" }, { type: :input, width: "half", label: "Vessel Model" }],
            [{ type: :divider }],
            [{ type: :section, label: "Rental Preferences" }],
            [{ type: :select, width: "half", label: "Slip Size Needed" }, { type: :select, width: "half", label: "Lease Term (Monthly, Seasonal, Annual)" }],
            [{ type: :date, width: "half", label: "Desired Start Date" }, { type: :select, width: "half", label: "Shore Power Required (30A, 50A, None)" }],
            [{ type: :checkbox, width: "full", label: "Desired Amenities (Live-Aboard, Pump-Out, Fuel Dock, Wi-Fi, Laundry, Security, Dock Cart)" }],
            [{ type: :file, width: "full", label: "Proof of Vessel Insurance (min $300K liability)" }],
            [{ type: :checkbox, width: "full", label: "I agree to abide by all marina rules, regulations, and safety policies" }]
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
              "file" => "full"
            },
            sections: [
              { label: "Owner Information", match_types: %w[text email tel] },
              { label: "Vessel & Slip Details", match_types: %w[number select date] },
              { label: "Amenities, Documents & Agreement", match_types: %w[checkbox file] }
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
