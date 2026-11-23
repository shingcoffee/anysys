# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Scheduling
      module AppointmentBooking
        DEFINITION = {
          key: "appointment_booking",
          name: "Appointment Booking",
          description: "Service booking with date/time slots and contact info",
          category: "scheduling",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Your Details" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :select, width: "half", label: "Preferred Contact Method" }],
            [{ type: :input, width: "half", label: "Company / Organization (optional)" }, { type: :select, width: "half", label: "How Did You Find Us?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Appointment Details" }],
            [{ type: :select, width: "half", label: "Service Type" }, { type: :select, width: "half", label: "Service Provider / Staff Member" }],
            [{ type: :select, width: "half", label: "Appointment Duration" }, { type: :select, width: "half", label: "Location (In-Person, Phone, Video)" }],
            [{ type: :date, width: "half", label: "Preferred Date" }, { type: :select, width: "half", label: "Preferred Time Slot" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time Slot" }],
            [{ type: :radio, width: "full", label: "Is this a new or returning appointment?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Additional Information" }],
            [{ type: :textarea, width: "full", label: "Reason for Appointment / Notes" }],
            [{ type: :checkbox, width: "full", label: "Send confirmation and reminder via email/SMS" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "time" => "half",
              "datetime-local" => "half",
            },
            sections: [
              { label: "Contact Information", match_types: %w[text email tel url] },
              { label: "Appointment Details", match_types: %w[date select radio time datetime-local month week] },
              { label: "Notes", match_types: %w[textarea checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
