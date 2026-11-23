# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Nonprofit
      module VolunteerRegistration
        DEFINITION = {
          key: "volunteer_registration",
          name: "Volunteer Registration",
          description: "Volunteer signup with availability, skills, and background check consent",
          category: "nonprofit",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "full", label: "Address" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Availability & Skills" }],
            [{ type: :date, width: "half", label: "Available Start Date" }, { type: :select, width: "half", label: "Hours Available Per Week" }],
            [{ type: :checkbox, width: "full", label: "Available Days: Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday" }],
            [{ type: :select, width: "half", label: "Preferred Time (Morning, Afternoon, Evening)" }, { type: :select, width: "half", label: "Volunteer Role Interest" }],
            [{ type: :checkbox, width: "full", label: "Skills & Certifications: First Aid, CPR, Driving, Cooking, Teaching, IT, Marketing, Languages, Medical, Carpentry" }],
            [{ type: :textarea, width: "full", label: "Relevant Experience & Why You Want to Volunteer" }],
            [{ type: :divider }],
            [{ type: :section, label: "Consent & Agreements" }],
            [{ type: :radio, width: "full", label: "Do you consent to a background check?" }],
            [{ type: :checkbox, width: "full", label: "I agree to the volunteer code of conduct and policies" }],
            [{ type: :checkbox, width: "full", label: "I understand this is a volunteer (unpaid) position" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Personal Info", match_types: %w[text email tel date] },
              { label: "Availability & Skills", match_types: %w[select checkbox textarea] },
              { label: "Consent", match_types: %w[radio] }
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
