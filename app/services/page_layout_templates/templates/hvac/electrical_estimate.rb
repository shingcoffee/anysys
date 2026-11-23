# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hvac
      module ElectricalEstimate
        DEFINITION = {
          key: "electrical_estimate",
          name: "Electrical Service Estimate",
          description: "Electrical work estimate request for residential or commercial wiring, panels, and installations",
          category: "hvac",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "full", label: "Service Address" }],
            [{ type: :select, width: "half", label: "Property Type (Residential, Commercial, Industrial)" }, { type: :radio, width: "half", label: "Own or Rent?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Electrical Details" }],
            [{ type: :select, width: "half", label: "Service Type (Repair, Installation, Upgrade, Inspection, New Construction)" }, { type: :select, width: "half", label: "Building Age" }],
            [{ type: :checkbox, width: "full", label: "Work Needed (Panel Upgrade, Wiring, Outlets/Switches, Lighting, EV Charger, Generator, Ceiling Fan, Smoke Detector, Other)" }],
            [{ type: :select, width: "half", label: "Current Panel Amperage (if known)" }, { type: :number, width: "half", label: "Number of Floors / Rooms Affected" }],
            [{ type: :radio, width: "full", label: "Is this an emergency?" }],
            [{ type: :radio, width: "full", label: "Is a permit required or previously pulled?" }],
            [{ type: :textarea, width: "full", label: "Describe the Electrical Work Needed" }],
            [{ type: :divider }],
            [{ type: :section, label: "Scheduling" }],
            [{ type: :date, width: "half", label: "Preferred Date" }, { type: :select, width: "half", label: "Preferred Time Window" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time Window" }],
            [{ type: :file, width: "full", label: "Photos of Area or Panel (optional)" }],
            [{ type: :checkbox, width: "full", label: "I authorize entry to assess and provide an estimate" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "number" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Contact & Location", match_types: %w[text email tel] },
              { label: "Electrical Details", match_types: %w[select number checkbox radio textarea] },
              { label: "Schedule & Photos", match_types: %w[date file time] }
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
