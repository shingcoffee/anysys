# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Homeservices
      module PlumbingService
        DEFINITION = {
          key: "plumbing_service",
          name: "Plumbing Service Request",
          description: "Plumbing service request with issue description, location, and scheduling preferences",
          category: "homeservices",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "full", label: "Service Address" }],
            [{ type: :select, width: "half", label: "Property Type (House, Condo, Apartment, Commercial)" }, { type: :radio, width: "half", label: "Own or Rent?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Issue Details" }],
            [{ type: :select, width: "half", label: "Issue Type (Leak, Clog, Low Pressure, No Hot Water, Burst Pipe, Installation, Other)" }, { type: :select, width: "half", label: "Urgency (Emergency, Same Day, Within a Week, Flexible)" }],
            [{ type: :select, width: "half", label: "Location in Home (Kitchen, Bathroom, Basement, Laundry, Outdoor, Multiple)" }, { type: :select, width: "half", label: "Number of Affected Fixtures" }],
            [{ type: :radio, width: "full", label: "Is water currently leaking or flooding?" }],
            [{ type: :radio, width: "full", label: "Have you had this issue before?" }],
            [{ type: :textarea, width: "full", label: "Describe the Problem in Detail" }],
            [{ type: :file, width: "full", label: "Photos or Video of Issue (optional)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Scheduling" }],
            [{ type: :date, width: "half", label: "Preferred Date" }, { type: :select, width: "half", label: "Preferred Time Window" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time Window" }],
            [{ type: :checkbox, width: "full", label: "I authorize entry to perform the service and agree to service call fees" }]
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
              "checkbox" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Issue Details", match_types: %w[select textarea radio file] },
              { label: "Scheduling", match_types: %w[date checkbox time] }
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
