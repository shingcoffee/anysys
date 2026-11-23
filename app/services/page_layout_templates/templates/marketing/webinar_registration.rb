# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Marketing
      module WebinarRegistration
        DEFINITION = {
          key: "webinar_registration",
          name: "Webinar Registration",
          description: "Online event registration with session selection and time zone",
          category: "marketing",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Attendee Information" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Work Email" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :input, width: "half", label: "Company" }, { type: :input, width: "half", label: "Job Title" }],
            [{ type: :select, width: "half", label: "Industry" }, { type: :select, width: "half", label: "Company Size" }],
            [{ type: :divider }],
            [{ type: :section, label: "Session Selection" }],
            [{ type: :select, width: "half", label: "Webinar / Session" }, { type: :select, width: "half", label: "Time Zone" }],
            [{ type: :date, width: "half", label: "Preferred Date" }, { type: :select, width: "half", label: "Preferred Time Slot" }],
            [{ type: :radio, width: "full", label: "How did you hear about this webinar?" }],
            [{ type: :textarea, width: "full", label: "Questions for the Speaker" }],
            [{ type: :checkbox, width: "full", label: "Send me a recording if I can't attend live" }],
            [{ type: :checkbox, width: "full", label: "I agree to receive follow-up communications" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Attendee Details", match_types: %w[text email tel select url] },
              { label: "Session & Questions", match_types: %w[date radio textarea] },
              { label: "Preferences", match_types: %w[checkbox] }
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
