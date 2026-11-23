# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hvac
      module AcRepairRequest
        DEFINITION = {
          key: "ac_repair_request",
          name: "AC / Heating Repair Request",
          description: "HVAC repair service request with system details, symptoms, and preferred scheduling",
          category: "hvac",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "full", label: "Service Address" }],
            [{ type: :select, width: "half", label: "Property Type (Residential, Commercial)" }, { type: :radio, width: "half", label: "Own or Rent?" }],
            [{ type: :divider }],
            [{ type: :section, label: "System Information" }],
            [{ type: :select, width: "half", label: "System Type (Central AC, Heat Pump, Furnace, Mini-Split, Boiler, Other)" }, { type: :input, width: "half", label: "Brand / Manufacturer" }],
            [{ type: :select, width: "half", label: "System Age (< 5 yrs, 5-10 yrs, 10-15 yrs, 15+ yrs)" }, { type: :select, width: "half", label: "Last Serviced" }],
            [{ type: :input, width: "half", label: "Model Number (if known)" }, { type: :input, width: "half", label: "Serial Number (if known)" }],
            [{ type: :radio, width: "full", label: "Is the system under warranty?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Issue Details & Scheduling" }],
            [{ type: :checkbox, width: "full", label: "Symptoms (Not Cooling, Not Heating, Strange Noise, Water Leak, Bad Smell, Short Cycling, High Bills, Other)" }],
            [{ type: :select, width: "half", label: "Urgency (Emergency, Same Day, Within a Week, Flexible)" }, { type: :select, width: "half", label: "Indoor Temperature Currently" }],
            [{ type: :textarea, width: "full", label: "Describe the Problem in Detail" }],
            [{ type: :date, width: "half", label: "Preferred Service Date" }, { type: :select, width: "half", label: "Preferred Time Window" }],
            [{ type: :file, width: "full", label: "Photos or Videos of Issue (optional)" }],
            [{ type: :checkbox, width: "full", label: "I authorize access to the property for service" }]
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
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Contact & Address", match_types: %w[text email tel] },
              { label: "System & Issue", match_types: %w[select radio checkbox textarea] },
              { label: "Scheduling & Photos", match_types: %w[date file time] }
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
