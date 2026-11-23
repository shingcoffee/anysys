# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Aviation
      module CharterRequest
        DEFINITION = {
          key: "aircraft_charter_request",
          name: "Aircraft Charter Request",
          description: "Private aircraft charter inquiry with trip details, passenger count, luggage, and special requirements",
          category: "aviation",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Primary Contact Name" }, { type: :input, width: "half", label: "Company / Organization" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Mobile Phone" }, { type: :input, width: "half", label: "Account Number (if existing client)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Trip & Passenger Details" }],
            [{ type: :input, width: "half", label: "Departure Airport / City (IATA Code)" }, { type: :input, width: "half", label: "Destination Airport / City (IATA Code)" }],
            [{ type: :date, width: "half", label: "Departure Date" }, { type: :select, width: "half", label: "Preferred Departure Time" }],
            [{ type: :radio, width: "full", label: "Is this a one-way or round-trip flight?" }],
            [{ type: :date, width: "half", label: "Return Date (if round-trip)" }, { type: :select, width: "half", label: "Preferred Return Time" }],
            [{ type: :input, width: "half", label: "Return Departure Airport" }, { type: :input, width: "half", label: "Return Destination Airport" }],
            [{ type: :number, width: "half", label: "Number of Passengers" }, { type: :number, width: "half", label: "Number of Checked Bags" }],
            [{ type: :number, width: "half", label: "Number of Carry-On Bags" }, { type: :radio, width: "half", label: "Any Oversized Items? (Golf Clubs, Skis, etc.)" }],
            [{ type: :select, width: "half", label: "Preferred Aircraft Type / Size" }, { type: :select, width: "half", label: "Cabin Configuration Preference" }],
            [{ type: :checkbox, width: "full", label: "Required Amenities (WiFi, Entertainment, Lie-Flat Seats, Conference Table, Lavatory, Refreshments Bar)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Special Requests" }],
            [{ type: :select, width: "half", label: "Catering Preference" }, { type: :select, width: "half", label: "Beverage Preference" }],
            [{ type: :textarea, width: "full", label: "Dietary Restrictions, Allergies, or Special Meal Requests" }],
            [{ type: :checkbox, width: "full", label: "Additional Services (Ground Transport, Hotel, Pet Accommodation, Medical Equipment, Extra Crew, Security)" }],
            [{ type: :select, width: "half", label: "Payment Method (Wire Transfer, Credit Card, Account Billing)" }, { type: :input, width: "half", label: "Billing Contact Name" }],
            [{ type: :textarea, width: "full", label: "Special Requests, VIP Requirements, or Additional Notes" }]
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
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact Information", match_types: %w[text email tel] },
              { label: "Trip & Passenger Details", match_types: %w[date number select radio checkbox] },
              { label: "Special Requests", match_types: %w[textarea] }
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
