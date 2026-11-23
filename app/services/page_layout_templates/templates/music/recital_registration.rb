# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Music
      module RecitalRegistration
        DEFINITION = {
          key: "music_recital_registration",
          name: "Music Recital Registration",
          description: "Student recital or performance registration with piece selection, instrument, and accompaniment needs",
          category: "music",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Student & Contact Information" }],
            [{ type: :input, width: "half", label: "Student Full Name" }, { type: :input, width: "half", label: "Parent / Guardian Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Instructor Name" }, { type: :input, width: "half", label: "Music School / Studio" }],
            [{ type: :divider }],
            [{ type: :section, label: "Performance Details" }],
            [{ type: :select, width: "half", label: "Instrument / Voice Type" }, { type: :select, width: "half", label: "Skill Level" }],
            [{ type: :input, width: "half", label: "Performance Piece Title" }, { type: :input, width: "half", label: "Composer" }],
            [{ type: :number, width: "half", label: "Approximate Duration (minutes)" }, { type: :select, width: "half", label: "Performance Category (Solo, Duet, Ensemble, Group)" }],
            [{ type: :input, width: "half", label: "Second Piece Title (if applicable)" }, { type: :input, width: "half", label: "Second Piece Composer" }],
            [{ type: :radio, width: "full", label: "Accompanist Needed?" }],
            [{ type: :radio, width: "full", label: "Do you need a music stand?" }],
            [{ type: :radio, width: "full", label: "Do you need a piano bench?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Logistics & Consent" }],
            [{ type: :number, width: "half", label: "Number of Guest Tickets Needed" }, { type: :select, width: "half", label: "T-Shirt Size (if provided)" }],
            [{ type: :file, width: "full", label: "Sheet Music for Accompanist (PDF)" }],
            [{ type: :textarea, width: "full", label: "Special Requests or Stage Requirements" }],
            [{ type: :checkbox, width: "full", label: "I agree to recital guidelines and consent to photos/videos being taken" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Student & Contact Info", match_types: %w[text email tel] },
              { label: "Performance Details", match_types: %w[select number radio] },
              { label: "Sheet Music & Requests", match_types: %w[textarea file checkbox] }
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
