# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hospitality
      module GuestCheckin
        DEFINITION = {
          key: "guest_checkin",
          name: "Guest Check-in",
          description: "Hotel or vacation rental guest registration with ID and preferences",
          category: "hospitality",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Guest Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Nationality" }],
            [{ type: :input, width: "half", label: "ID / Passport Number" }, { type: :select, width: "half", label: "ID Type (Passport, Driver's License, National ID)" }],
            [{ type: :input, width: "half", label: "Country of Residence" }, { type: :select, width: "half", label: "Purpose of Visit (Leisure, Business, Special Occasion)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Reservation Details" }],
            [{ type: :date, width: "half", label: "Check-in Date" }, { type: :date, width: "half", label: "Check-out Date" }],
            [{ type: :input, width: "half", label: "Reservation / Confirmation Number" }, { type: :input, width: "half", label: "Room Number" }],
            [{ type: :number, width: "half", label: "Number of Guests" }, { type: :select, width: "half", label: "Booking Source (Direct, Expedia, Booking.com, Airbnb, Other)" }],
            [{ type: :select, width: "half", label: "Payment Method" }, { type: :number, width: "half", label: "Vehicle License Plate (for parking)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Preferences & Documents" }],
            [{ type: :radio, width: "full", label: "Bed Preference (King, Queen, Twin, No Preference)" }],
            [{ type: :checkbox, width: "full", label: "Special Requests (High Floor, Non-Smoking, Quiet Room, Accessible, Early Check-in, Late Check-out, Extra Pillows, Crib)" }],
            [{ type: :file, width: "full", label: "Upload Government ID" }],
            [{ type: :checkbox, width: "full", label: "I agree to the hotel's terms, policies, and any applicable fees" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Guest Information", match_types: %w[text email tel select] },
              { label: "Reservation Details", match_types: %w[date number] },
              { label: "Preferences & Documents", match_types: %w[radio checkbox file] }
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
