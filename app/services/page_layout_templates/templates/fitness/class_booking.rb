# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Fitness
      module ClassBooking
        DEFINITION = {
          key: "class_booking",
          name: "Class Booking",
          description: "Fitness class reservation with schedule, instructor, and level selection",
          category: "fitness",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Your Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Member ID (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Class Selection" }],
            [{ type: :select, width: "half", label: "Class Type (Yoga, Pilates, HIIT, Spin, Zumba, Boxing, CrossFit, Other)" }, { type: :select, width: "half", label: "Instructor" }],
            [{ type: :date, width: "half", label: "Booking Date" }, { type: :select, width: "half", label: "Time Slot" }],
            [{ type: :select, width: "half", label: "Fitness Level (Beginner, Intermediate, Advanced)" }, { type: :select, width: "half", label: "Location / Studio" }],
            [{ type: :number, width: "half", label: "Number of Spots to Reserve" }, { type: :radio, width: "half", label: "Recurring weekly booking?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Health Notes" }],
            [{ type: :checkbox, width: "full", label: "Equipment I Have (Mat, Weights, Resistance Bands, Jump Rope, Foam Roller, Towel)" }],
            [{ type: :textarea, width: "full", label: "Injuries, Limitations, or Medical Conditions" }],
            [{ type: :radio, width: "full", label: "Is this your first time taking this class?" }],
            [{ type: :checkbox, width: "full", label: "I understand the physical demands of this class and participate at my own risk" }]
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
              { label: "Your Info", match_types: %w[text email tel] },
              { label: "Class Selection", match_types: %w[select date number radio time] },
              { label: "Health Notes", match_types: %w[checkbox textarea] }
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
