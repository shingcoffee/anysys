# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Marine
      module BoatService
        DEFINITION = {
          key: "boat_service_request",
          name: "Boat Service Request",
          description: "Marine vessel service and repair request with boat details, engine info, and service type",
          category: "marine",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Owner Information" }],
            [{ type: :input, width: "half", label: "Owner Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Marina / Slip Location" }],
            [{ type: :divider }],
            [{ type: :section, label: "Vessel Information" }],
            [{ type: :input, width: "half", label: "Boat Make" }, { type: :input, width: "half", label: "Boat Model" }],
            [{ type: :number, width: "half", label: "Year" }, { type: :input, width: "half", label: "Hull ID / Registration Number" }],
            [{ type: :select, width: "half", label: "Boat Type (Powerboat, Sailboat, Pontoon, Fishing, PWC, Other)" }, { type: :select, width: "half", label: "Engine Type (Inboard, Outboard, Stern Drive, Electric, Diesel)" }],
            [{ type: :input, width: "half", label: "Vessel Length (feet)" }, { type: :input, width: "half", label: "Engine Hours (approximate)" }],
            [{ type: :input, width: "half", label: "Engine Make / Model" }, { type: :input, width: "half", label: "Engine Serial Number" }],
            [{ type: :divider }],
            [{ type: :section, label: "Service Needed" }],
            [{ type: :checkbox, width: "full", label: "Services Requested (Engine Repair, Oil Change, Bottom Paint, Winterization, Electronics, Rigging, Hull Repair, Detailing, Annual Service)" }],
            [{ type: :select, width: "half", label: "Priority (Emergency, High, Normal, Scheduled)" }, { type: :date, width: "half", label: "Preferred Service Date" }],
            [{ type: :textarea, width: "full", label: "Describe the Issue or Service Needed" }],
            [{ type: :file, width: "full", label: "Photos of Issue (optional)" }],
            [{ type: :checkbox, width: "full", label: "I authorize diagnosis and provide consent for the service quote" }]
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
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Owner & Location", match_types: %w[text email tel] },
              { label: "Vessel & Service Details", match_types: %w[number select date checkbox] },
              { label: "Description & Photos", match_types: %w[textarea file] }
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
