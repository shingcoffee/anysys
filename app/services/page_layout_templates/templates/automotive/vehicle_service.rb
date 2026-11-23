# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Automotive
      module VehicleService
        DEFINITION = {
          key: "vehicle_service",
          name: "Vehicle Service Appointment",
          description: "Auto service booking with vehicle info, service type, and scheduling",
          category: "automotive",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Customer Info" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "full", label: "Street Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :radio, width: "full", label: "Are you an existing customer?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Vehicle Details" }],
            [{ type: :select, width: "third", label: "Year" }, { type: :select, width: "third", label: "Make" }, { type: :select, width: "third", label: "Model" }],
            [{ type: :input, width: "half", label: "Trim / Engine Size" }, { type: :select, width: "half", label: "Transmission Type (Automatic, Manual)" }],
            [{ type: :input, width: "half", label: "VIN (Vehicle ID Number)" }, { type: :input, width: "half", label: "License Plate Number" }],
            [{ type: :number, width: "half", label: "Current Mileage" }, { type: :select, width: "half", label: "Fuel Type (Gas, Diesel, Hybrid, Electric)" }],
            [{ type: :input, width: "half", label: "Exterior Color" }, { type: :date, width: "half", label: "Last Service Date (if known)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Service & Schedule" }],
            [{ type: :checkbox, width: "full", label: "Services Requested (Oil Change, Tire Rotation, Brake Inspection, Battery Check, Air Filter, Transmission Service, Coolant Flush, Wheel Alignment, State Inspection, Engine Diagnostic, AC Service, Wipers, Detailing)" }],
            [{ type: :radio, width: "full", label: "Is this a recall or warranty service?" }],
            [{ type: :input, width: "full", label: "Recall / Campaign Number (if applicable)" }],
            [{ type: :textarea, width: "full", label: "Describe Symptoms, Noises, or Concerns" }],
            [{ type: :date, width: "half", label: "Preferred Appointment Date" }, { type: :select, width: "half", label: "Preferred Time Slot" }],
            [{ type: :select, width: "half", label: "Service Location / Dealership" }, { type: :select, width: "half", label: "Drop-Off or Wait?" }],
            [{ type: :radio, width: "full", label: "Will you need a loaner vehicle or shuttle service?" }],
            [{ type: :select, width: "full", label: "Preferred Contact Method for Updates (Call, Text, Email)" }],
            [{ type: :textarea, width: "full", label: "Additional Notes or Special Requests" }]
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
              "time" => "half",
            },
            sections: [
              { label: "Customer Info", match_types: %w[text email tel radio] },
              { label: "Vehicle Details", match_types: %w[select number date] },
              { label: "Service & Schedule", match_types: %w[checkbox textarea time] }
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
