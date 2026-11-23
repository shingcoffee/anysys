# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Travel
      module TravelRequest
        DEFINITION = {
          key: "travel_request",
          name: "Travel Request",
          description: "Corporate travel request with itinerary, budget, and approvals",
          category: "travel",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Traveler Information" }],
            [{ type: :input, width: "half", label: "Employee Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :input, width: "half", label: "Department" }, { type: :input, width: "half", label: "Manager / Approver Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :divider }],
            [{ type: :section, label: "Trip Details" }],
            [{ type: :input, width: "half", label: "Destination City / Country" }, { type: :select, width: "half", label: "Purpose of Travel" }],
            [{ type: :date, width: "half", label: "Departure Date" }, { type: :date, width: "half", label: "Return Date" }],
            [{ type: :select, width: "half", label: "Primary Transport (Flight, Train, Car, Bus)" }, { type: :select, width: "half", label: "Class of Travel (Economy, Business, First)" }],
            [{ type: :radio, width: "full", label: "Accommodation Required?" }],
            [{ type: :select, width: "half", label: "Hotel Category (3-star, 4-star, 5-star)" }, { type: :number, width: "half", label: "Number of Nights" }],
            [{ type: :divider }],
            [{ type: :section, label: "Budget & Approvals" }],
            [{ type: :number, width: "half", label: "Estimated Total Budget ($)" }, { type: :input, width: "half", label: "Cost Center / Project Code" }],
            [{ type: :number, width: "half", label: "Flight Budget ($)" }, { type: :number, width: "half", label: "Hotel Budget ($)" }],
            [{ type: :number, width: "half", label: "Meals & Per Diem ($)" }, { type: :number, width: "half", label: "Other Expenses ($)" }],
            [{ type: :checkbox, width: "full", label: "Additional Services Needed (Rental Car, Visa Assistance, Travel Insurance, Airport Transfer)" }],
            [{ type: :textarea, width: "full", label: "Justification / Business Purpose" }],
            [{ type: :textarea, width: "full", label: "Additional Notes or Special Requirements" }],
            [{ type: :checkbox, width: "full", label: "I confirm this travel is necessary for business and within policy" }]
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
              "textarea" => "full",
              "checkbox" => "full",
              "time" => "half",
              "datetime-local" => "half",
            },
            sections: [
              { label: "Traveler Information", match_types: %w[text email tel url] },
              { label: "Trip Details", match_types: %w[date select number radio time datetime-local] },
              { label: "Budget & Approvals", match_types: %w[textarea checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
