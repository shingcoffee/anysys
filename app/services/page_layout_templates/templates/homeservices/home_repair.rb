# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Homeservices
      module HomeRepair
        DEFINITION = {
          key: "home_repair",
          name: "Home Repair Request",
          description: "Residential repair or maintenance service request with photos and urgency",
          category: "homeservices",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Service Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :select, width: "half", label: "Property Type (House, Condo, Apartment, Townhome, Commercial)" }, { type: :radio, width: "half", label: "Do you own or rent this property?" }],
            [{ type: :select, width: "half", label: "How Did You Hear About Us?" }, { type: :radio, width: "half", label: "Have you used our services before?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Service Details" }],
            [{ type: :select, width: "half", label: "Service Type (Plumbing, Electrical, HVAC, Roofing, Painting, Flooring, Carpentry, Appliance Repair, Landscaping, Other)" }, { type: :select, width: "half", label: "Urgency (Routine, Soon Within 1 Week, Urgent, Emergency)" }],
            [{ type: :textarea, width: "full", label: "Describe the Issue or Work Needed in Detail" }],
            [{ type: :file, width: "full", label: "Upload Photos of the Problem Area" }],
            [{ type: :divider }],
            [{ type: :section, label: "Scheduling" }],
            [{ type: :date, width: "half", label: "Preferred Date" }, { type: :select, width: "half", label: "Preferred Time Window (Morning, Afternoon, Evening)" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time Window" }],
            [{ type: :radio, width: "full", label: "Is someone home during the service?" }],
            [{ type: :textarea, width: "full", label: "Access Instructions, Gate Code, or Special Notes" }]
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
              { label: "Contact Info", match_types: %w[text email tel select radio] },
              { label: "Service Details", match_types: %w[textarea file time] },
              { label: "Scheduling", match_types: %w[date] }
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
