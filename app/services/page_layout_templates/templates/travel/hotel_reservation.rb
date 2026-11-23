# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Travel
      module HotelReservation
        DEFINITION = {
          key: "hotel_reservation",
          name: "Hotel Reservation",
          description: "Guest booking with room type, check-in/out, and special requests",
          category: "travel",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Guest Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :select, width: "half", label: "Country of Residence" }],
            [{ type: :select, width: "half", label: "ID Type (Passport, Driver's License, National ID)" }, { type: :input, width: "half", label: "ID Number" }],
            [{ type: :divider }],
            [{ type: :section, label: "Reservation Details" }],
            [{ type: :date, width: "half", label: "Check-in Date" }, { type: :date, width: "half", label: "Check-out Date" }],
            [{ type: :number, width: "half", label: "Number of Adults" }, { type: :number, width: "half", label: "Number of Children" }],
            [{ type: :select, width: "half", label: "Room Type (Standard, Deluxe, Suite, Family, Accessible)" }, { type: :select, width: "half", label: "Bed Type (Single, Double, Twin, King, Queen)" }],
            [{ type: :number, width: "half", label: "Number of Rooms" }, { type: :select, width: "half", label: "Floor Preference (Low, Mid, High, No Preference)" }],
            [{ type: :select, width: "half", label: "Meal Plan (Room Only, B&B, Half Board, Full Board)" }, { type: :select, width: "half", label: "Rate Plan / Promotion Code" }],
            [{ type: :divider }],
            [{ type: :section, label: "Requests & Extras" }],
            [{ type: :checkbox, width: "full", label: "Room Preferences (Non-Smoking, Smoking, Sea View, Garden View, Quiet Room)" }],
            [{ type: :checkbox, width: "full", label: "Add-ons (Airport Transfer, Breakfast, Parking, Spa Access, Early Check-in, Late Checkout)" }],
            [{ type: :radio, width: "full", label: "Purpose of Stay (Leisure, Business, Honeymoon, Event/Conference)" }],
            [{ type: :textarea, width: "full", label: "Special Requests or Notes" }],
            [{ type: :select, width: "half", label: "Payment Method" }, { type: :radio, width: "half", label: "Booking Confirmation Preference (Email, SMS, Both)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Guest Details", match_types: %w[text email tel url] },
              { label: "Stay Details", match_types: %w[date number select radio time datetime-local] },
              { label: "Requests & Extras", match_types: %w[textarea checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
