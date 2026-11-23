# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Facilities
      module MaintenanceRequest
        DEFINITION = {
          key: "maintenance_request",
          name: "Maintenance Request",
          description: "Facility maintenance or repair request with location, priority, and photos",
          category: "facilities",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Requester Info" }],
            [{ type: :input, width: "half", label: "Requester Name" }, { type: :input, width: "half", label: "Department" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Employee ID (if applicable)" }, { type: :select, width: "half", label: "Preferred Contact Method" }],
            [{ type: :divider }],
            [{ type: :section, label: "Issue Details" }],
            [{ type: :select, width: "half", label: "Issue Category (Electrical, Plumbing, HVAC, Structural, IT, Safety, Cleaning, Pest, Other)" }, { type: :select, width: "half", label: "Priority (Low, Normal, High, Emergency)" }],
            [{ type: :input, width: "half", label: "Building / Facility Name" }, { type: :input, width: "half", label: "Floor / Room Number" }],
            [{ type: :radio, width: "full", label: "Is the area safe and still usable?" }],
            [{ type: :radio, width: "full", label: "Is this an ongoing or recurring issue?" }],
            [{ type: :date, width: "half", label: "Date Issue Was Noticed" }, { type: :select, width: "half", label: "Estimated Impact (Individual, Team, Entire Floor, Building)" }],
            [{ type: :textarea, width: "full", label: "Describe the Issue in Detail" }],
            [{ type: :file, width: "full", label: "Upload Photos or Videos of the Issue" }],
            [{ type: :divider }],
            [{ type: :section, label: "Scheduling" }],
            [{ type: :date, width: "half", label: "Preferred Repair Date" }, { type: :select, width: "half", label: "Best Time for Access" }],
            [{ type: :radio, width: "full", label: "Can the technician enter without you present?" }],
            [{ type: :textarea, width: "full", label: "Additional Notes or Access Instructions" }]
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
              "textarea" => "full",
              "file" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Requester Info", match_types: %w[text email tel] },
              { label: "Issue Details", match_types: %w[select date radio textarea file time] },
              { label: "Scheduling", match_types: %w[radio textarea date] }
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
