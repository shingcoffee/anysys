# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Mentalhealth
      module CounselingFeedback
        DEFINITION = {
          key: "counseling_feedback",
          name: "Counseling Session Feedback",
          description: "Post-session feedback with mood tracking, progress rating, and therapist evaluation",
          category: "mentalhealth",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Session Information" }],
            [{ type: :input, width: "half", label: "Client Name" }, { type: :date, width: "half", label: "Session Date" }],
            [{ type: :input, width: "half", label: "Therapist / Counselor Name" }, { type: :select, width: "half", label: "Session Type (Individual, Couples, Group, Crisis, Check-in)" }],
            [{ type: :select, width: "half", label: "Session Format (In-Person, Video, Phone)" }, { type: :select, width: "half", label: "Session Duration" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Experience" }],
            [{ type: :select, width: "half", label: "Current Mood (1-10)" }, { type: :select, width: "half", label: "Energy Level (Very Low → Very High)" }],
            [{ type: :select, width: "half", label: "Anxiety Level (1-10)" }, { type: :select, width: "half", label: "Overall Session Rating (1-5)" }],
            [{ type: :radio, width: "full", label: "Did you feel heard and understood?" }],
            [{ type: :radio, width: "full", label: "Did you feel safe during this session?" }],
            [{ type: :radio, width: "full", label: "Would you like to adjust session frequency?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Reflections & Goals" }],
            [{ type: :textarea, width: "full", label: "Key takeaways or insights from this session" }],
            [{ type: :textarea, width: "full", label: "Goals or intentions for before next session" }],
            [{ type: :textarea, width: "full", label: "Anything you would like your therapist to know or explore next session?" }],
            [{ type: :checkbox, width: "full", label: "I consent to my feedback being used to improve my care plan" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Session Info", match_types: %w[text email date select] },
              { label: "Your Experience", match_types: %w[radio] },
              { label: "Reflections", match_types: %w[textarea checkbox] }
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
