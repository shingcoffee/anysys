# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Facilities
      module ParkingPermit
        DEFINITION = {
          key: "parking_permit",
          name: "Parking Permit Application",
          description: "Employee or visitor parking permit request with vehicle details and lot preference",
          category: "facilities",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Applicant Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Employee / Student ID" }],
            [{ type: :input, width: "half", label: "Department / Unit" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :select, width: "half", label: "Applicant Type (Employee, Contractor, Student, Visitor)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Vehicle Information" }],
            [{ type: :input, width: "half", label: "License Plate Number" }, { type: :input, width: "half", label: "State / Province" }],
            [{ type: :input, width: "half", label: "Vehicle Make & Model" }, { type: :input, width: "half", label: "Vehicle Color" }],
            [{ type: :input, width: "half", label: "Vehicle Year" }, { type: :select, width: "half", label: "Vehicle Type (Car, Truck, Van, Motorcycle, EV, Other)" }],
            [{ type: :radio, width: "full", label: "Does the vehicle require EV charging?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Permit Details" }],
            [{ type: :select, width: "half", label: "Permit Type (Daily, Monthly, Annual, Visitor)" }, { type: :select, width: "half", label: "Preferred Parking Lot / Zone" }],
            [{ type: :date, width: "half", label: "Permit Start Date" }, { type: :date, width: "half", label: "Permit End Date" }],
            [{ type: :radio, width: "full", label: "Do you require accessible / disability parking?" }],
            [{ type: :input, width: "half", label: "Accessibility Permit Number (if applicable)" }, { type: :select, width: "half", label: "Payment Method" }],
            [{ type: :checkbox, width: "full", label: "I agree to abide by all parking rules, regulations, and enforcement policies" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Employee Info", match_types: %w[text email tel] },
              { label: "Vehicle & Permit", match_types: %w[select date radio] },
              { label: "Agreement", match_types: %w[checkbox] }
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
