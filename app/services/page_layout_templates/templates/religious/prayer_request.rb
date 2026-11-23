# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Religious
      module PrayerRequest
        DEFINITION = {
          key: "prayer_request",
          name: "Prayer Request",
          description: "Confidential prayer request submission with category and follow-up preferences",
          category: "religious",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Your Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :select, width: "half", label: "Preferred Contact Method (Email, Phone, No Contact)" }],
            [{ type: :select, width: "half", label: "Congregation / Campus (if applicable)" }, { type: :select, width: "half", label: "Member Status (Member, Regular Attendee, Visitor, Online)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Request" }],
            [{ type: :select, width: "half", label: "Request Category (Health, Family, Finances, Relationships, Grief, Guidance, Praise, Other)" }, { type: :select, width: "half", label: "Urgency (Routine, This Week, Urgent)" }],
            [{ type: :textarea, width: "full", label: "Prayer Request (Please share as much or as little as you are comfortable with)" }],
            [{ type: :input, width: "full", label: "Name(s) to Pray For (if praying for someone else)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Preferences & Follow-up" }],
            [{ type: :radio, width: "full", label: "May we share this request with our prayer team?" }],
            [{ type: :radio, width: "full", label: "Would you like pastoral follow-up or a personal call?" }],
            [{ type: :radio, width: "full", label: "Would you like to be added to our ongoing prayer list?" }],
            [{ type: :checkbox, width: "full", label: "Please keep my name and details confidential" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Your Request", match_types: %w[select textarea] },
              { label: "Preferences", match_types: %w[radio checkbox] }
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
