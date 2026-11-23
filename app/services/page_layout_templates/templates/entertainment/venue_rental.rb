# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Entertainment
      module VenueRental
        DEFINITION = {
          key: "venue_rental",
          name: "Venue Rental",
          description: "Event venue rental inquiry with date, capacity, catering, and AV requirements",
          category: "entertainment",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Contact Name" }, { type: :input, width: "half", label: "Organization / Company" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :divider }],
            [{ type: :section, label: "Event Details" }],
            [{ type: :select, width: "half", label: "Event Type (Wedding, Corporate, Birthday, Concert, Conference, Other)" }, { type: :number, width: "half", label: "Expected Number of Guests" }],
            [{ type: :date, width: "half", label: "Event Date" }, { type: :date, width: "half", label: "Alternate Date" }],
            [{ type: :select, width: "half", label: "Event Start Time" }, { type: :select, width: "half", label: "Duration (hrs)" }],
            [{ type: :select, width: "half", label: "Preferred Venue Space / Room" }, { type: :select, width: "half", label: "Setup Style (Banquet, Theater, Classroom, Cocktail, Custom)" }],
            [{ type: :number, width: "half", label: "Budget Range ($)" }, { type: :select, width: "half", label: "Alcohol Service (None, Beer/Wine, Full Bar)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Services & Equipment" }],
            [{ type: :checkbox, width: "full", label: "Services Needed (Catering, Bar Service, Security, Valet, Floral, Photography, DJ/Band)" }],
            [{ type: :checkbox, width: "full", label: "AV Equipment (Projector, Screen, Microphone, Sound System, Lighting, Stage, Live Stream)" }],
            [{ type: :radio, width: "full", label: "Will vendors be brought in externally?" }],
            [{ type: :textarea, width: "full", label: "Event Description & Special Requests" }],
            [{ type: :checkbox, width: "full", label: "I understand a deposit is required to confirm booking" }]
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
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Event Details", match_types: %w[select date number radio time] },
              { label: "Services & Notes", match_types: %w[checkbox textarea] }
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
