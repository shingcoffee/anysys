# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Music
      module LessonSignup
        DEFINITION = {
          key: "music_lesson_signup",
          name: "Music Lesson Signup",
          description: "Music lesson enrollment with instrument selection, experience level, and scheduling preferences",
          category: "music",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Student Information" }],
            [{ type: :input, width: "half", label: "Student Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Parent / Guardian Name (if minor)" }, { type: :input, width: "half", label: "Parent / Guardian Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Lesson Preferences" }],
            [{ type: :select, width: "half", label: "Instrument (Piano, Guitar, Violin, Drums, Voice, Flute, Bass, Ukulele, Other)" }, { type: :select, width: "half", label: "Experience Level (Beginner, Elementary, Intermediate, Advanced)" }],
            [{ type: :select, width: "half", label: "Lesson Length (30 min, 45 min, 60 min)" }, { type: :select, width: "half", label: "Lesson Format (In-Person, Online, Either)" }],
            [{ type: :select, width: "half", label: "Instructor Preference (No Preference, specific name)" }, { type: :select, width: "half", label: "Music Genre Focus (Classical, Pop, Jazz, Rock, Country, Other)" }],
            [{ type: :checkbox, width: "full", label: "Preferred Days (Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday)" }],
            [{ type: :select, width: "half", label: "Preferred Time of Day" }, { type: :select, width: "half", label: "Lesson Frequency (Weekly, Bi-Weekly)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Goals & Additional Info" }],
            [{ type: :textarea, width: "full", label: "Musical Goals and Favorite Genres or Artists" }],
            [{ type: :radio, width: "full", label: "Do you own your instrument?" }],
            [{ type: :radio, width: "full", label: "Interested in participating in recitals or performances?" }],
            [{ type: :checkbox, width: "full", label: "I agree to the lesson cancellation policy and payment terms" }]
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
              { label: "Student Info", match_types: %w[text email tel date] },
              { label: "Lesson Details", match_types: %w[select checkbox] },
              { label: "Goals & Preferences", match_types: %w[textarea radio] }
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
