# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Coworking
      module DeskBooking
        DEFINITION = {
          key: "desk_booking",
          name: "Desk Booking",
          description: "Hot-desk or dedicated workspace reservation with date, time, and amenities",
          category: "coworking",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Contact Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Member ID (if applicable)" }],
            [{ type: :input, width: "half", label: "Company / Organization" }, { type: :select, width: "half", label: "Member Type (Day Pass, Member, Non-Member)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Booking Details" }],
            [{ type: :select, width: "half", label: "Location / Floor" }, { type: :select, width: "half", label: "Desk Type (Hot Desk, Standing Desk, Private Room, Pod, Quiet Zone)" }],
            [{ type: :date, width: "half", label: "Booking Date" }, { type: :select, width: "half", label: "Duration (Half Day, Full Day, Weekly, Monthly)" }],
            [{ type: :select, width: "half", label: "Start Time" }, { type: :select, width: "half", label: "End Time" }],
            [{ type: :number, width: "half", label: "Number of Guests" }, { type: :radio, width: "half", label: "Recurring Booking?" }],
            [{ type: :select, width: "full", label: "Recurrence Frequency (One-time, Daily, Weekly, Monthly)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Amenities & Notes" }],
            [{ type: :checkbox, width: "full", label: "Amenities Needed (Monitor, Whiteboard, Phone, Printer, Locker, Parking, Coffee/Tea, Standing Mat)" }],
            [{ type: :textarea, width: "full", label: "Special Requests or Accessibility Needs" }],
            [{ type: :checkbox, width: "full", label: "I agree to the workspace usage policies and will leave the area clean for the next user" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Booking Details", match_types: %w[select date number radio time] },
              { label: "Amenities & Notes", match_types: %w[checkbox textarea] }
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
