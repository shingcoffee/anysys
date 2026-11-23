# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Facilities
      module RoomBooking
        DEFINITION = {
          key: "room_booking",
          name: "Room Booking",
          description: "Meeting room or facility space reservation with equipment and catering needs",
          category: "facilities",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Requester Info" }],
            [{ type: :input, width: "half", label: "Requester Name" }, { type: :input, width: "half", label: "Department" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Cost Center / Account Code" }, { type: :select, width: "half", label: "Manager Approval Required?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Booking Details" }],
            [{ type: :select, width: "half", label: "Room / Space" }, { type: :number, width: "half", label: "Number of Attendees" }],
            [{ type: :date, width: "half", label: "Booking Date" }, { type: :select, width: "half", label: "Start Time" }],
            [{ type: :select, width: "half", label: "End Time" }, { type: :select, width: "half", label: "Recurrence (One-Time, Daily, Weekly, Monthly)" }],
            [{ type: :input, width: "full", label: "Meeting Title / Purpose" }],
            [{ type: :radio, width: "full", label: "Internal or External attendees?" }],
            [{ type: :radio, width: "full", label: "Is this a confidential meeting?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Setup & Equipment" }],
            [{ type: :checkbox, width: "full", label: "AV Equipment Needed (Projector, Video Conferencing, Whiteboard, TV Screen, Microphone, Speakers, Laptop)" }],
            [{ type: :checkbox, width: "full", label: "Catering Needed (Coffee, Tea, Water, Snacks, Breakfast, Lunch, Full Catering Service)" }],
            [{ type: :select, width: "half", label: "Room Setup Style (Boardroom, Classroom, U-Shape, Theater, Reception)" }, { type: :number, width: "half", label: "Number of Chairs Required" }],
            [{ type: :textarea, width: "full", label: "Setup Instructions or Special Requests" }]
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
              { label: "Requester Info", match_types: %w[text email tel select] },
              { label: "Booking Details", match_types: %w[date number radio time] },
              { label: "Setup & Equipment", match_types: %w[checkbox textarea] }
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
