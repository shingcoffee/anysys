# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Entertainment
      module TicketBooking
        DEFINITION = {
          key: "ticket_booking",
          name: "Ticket Booking",
          description: "Event or show ticket purchase with seat selection and attendee info",
          category: "entertainment",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Event Selection" }],
            [{ type: :select, width: "full", label: "Event / Show" }],
            [{ type: :date, width: "half", label: "Date" }, { type: :select, width: "half", label: "Time" }],
            [{ type: :select, width: "half", label: "Venue / Location" }, { type: :select, width: "half", label: "Seating Section" }],
            [{ type: :divider }],
            [{ type: :section, label: "Ticket Options" }],
            [{ type: :select, width: "half", label: "Ticket Type (General, VIP, Early Bird, Group)" }, { type: :select, width: "half", label: "Price Tier" }],
            [{ type: :number, width: "half", label: "Adult Tickets" }, { type: :number, width: "half", label: "Child Tickets" }],
            [{ type: :checkbox, width: "full", label: "Add-ons: Parking Pass, VIP Lounge, Merchandise Bundle, Meet & Greet, Program" }],
            [{ type: :divider }],
            [{ type: :section, label: "Attendee Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :select, width: "half", label: "How did you hear about us?" }],
            [{ type: :radio, width: "full", label: "Accessibility / Special Requirements?" }],
            [{ type: :input, width: "half", label: "Promo Code" }, { type: :select, width: "half", label: "Payment Method" }]
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
              { label: "Event Selection", match_types: %w[select date time] },
              { label: "Ticket Options", match_types: %w[number checkbox] },
              { label: "Attendee Info", match_types: %w[text email tel radio] }
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
