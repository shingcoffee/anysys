# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Scheduling
      module EventRegistration
        DEFINITION = {
          key: "event_registration",
          name: "Event Registration",
          description: "RSVP form with date selection, meal choice, and guest count",
          category: "scheduling",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Attendee Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Organization / Company" }],
            [{ type: :divider }],
            [{ type: :section, label: "Event Details" }],
            [{ type: :select, width: "half", label: "Event Name / Type" }, { type: :date, width: "half", label: "Event Date" }],
            [{ type: :select, width: "half", label: "Session / Time Slot" }, { type: :select, width: "half", label: "Location / Venue" }],
            [{ type: :number, width: "half", label: "Number of Guests" }, { type: :select, width: "half", label: "Registration Type (General, VIP, Student, Press)" }],
            [{ type: :select, width: "half", label: "Meal Preference" }, { type: :select, width: "half", label: "T-Shirt Size (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Preferences & Notes" }],
            [{ type: :checkbox, width: "full", label: "Dietary Restrictions (Vegetarian, Vegan, Gluten-Free, Nut Allergy)" }],
            [{ type: :radio, width: "full", label: "Require accessibility accommodations?" }],
            [{ type: :input, width: "half", label: "Promo Code (if any)" }, { type: :select, width: "half", label: "How Did You Hear About This Event?" }],
            [{ type: :textarea, width: "full", label: "Special Requests or Notes" }],
            [{ type: :checkbox, width: "full", label: "I agree to the event terms and cancellation policy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "time" => "half",
              "datetime-local" => "half",
              "month" => "half",
              "week" => "half",
            },
            sections: [
              { label: "Attendee Information", match_types: %w[text email tel url] },
              { label: "Event Details", match_types: %w[date select number radio time datetime-local month week] },
              { label: "Additional Info", match_types: %w[textarea checkbox] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
