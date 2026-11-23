# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Aviation
      module FlightTraining
        DEFINITION = {
          key: "flight_training_enrollment",
          name: "Flight Training Enrollment",
          description: "Pilot training program enrollment with experience level, certificate goals, medical status, and schedule",
          category: "aviation",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :input, width: "half", label: "Place of Birth (City, State)" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :divider }],
            [{ type: :section, label: "Experience & Preferences" }],
            [{ type: :select, width: "half", label: "Current Pilot Certificate (None, Student, Sport, Private, Commercial, ATP)" }, { type: :input, width: "half", label: "Certificate Number (if applicable)" }],
            [{ type: :select, width: "half", label: "Training Goal / Certificate Sought" }, { type: :checkbox, width: "half", label: "Ratings Desired (Instrument, Multi-Engine, CFI, CFII, MEI)" }],
            [{ type: :number, width: "half", label: "Total Flight Hours Logged" }, { type: :number, width: "half", label: "Pilot-in-Command (PIC) Hours" }],
            [{ type: :number, width: "half", label: "Cross-Country Hours" }, { type: :number, width: "half", label: "Instrument / Night Hours" }],
            [{ type: :radio, width: "full", label: "Do you currently hold a valid FAA Medical Certificate?" }],
            [{ type: :select, width: "half", label: "Medical Certificate Class (1st, 2nd, 3rd, BasicMed)" }, { type: :date, width: "half", label: "Medical Certificate Expiration Date" }],
            [{ type: :radio, width: "full", label: "Any medical conditions, medications, or FAA restrictions?" }],
            [{ type: :select, width: "half", label: "Preferred Training Aircraft Type" }, { type: :select, width: "half", label: "Preferred Training Location / Airport" }],
            [{ type: :select, width: "half", label: "Training Frequency (Full-Time, Part-Time, Weekends)" }, { type: :date, width: "half", label: "Desired Start Date" }],
            [{ type: :checkbox, width: "full", label: "Availability (Weekday Mornings, Weekday Afternoons, Weekday Evenings, Weekends, Flexible)" }],
            [{ type: :select, width: "half", label: "Estimated Training Budget Range" }, { type: :radio, width: "half", label: "Interested in Financing Options?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Goals & Documents" }],
            [{ type: :textarea, width: "full", label: "Aviation Goals & Career Aspirations (Commercial, Airline, Military, Corporate, Personal)" }],
            [{ type: :textarea, width: "full", label: "Previous Flight Training Experience or Schools Attended" }],
            [{ type: :file, width: "full", label: "Copy of Current Pilot Certificate, Medical Certificate & Government-Issued ID" }],
            [{ type: :radio, width: "full", label: "Are you a U.S. Citizen or Permanent Resident?" }],
            [{ type: :textarea, width: "full", label: "TSA Citizenship Verification Notes (Non-U.S. Citizens — IACRA/TSA clearance required)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Personal Information", match_types: %w[text email tel] },
              { label: "Experience & Preferences", match_types: %w[select date number radio checkbox] },
              { label: "Goals & Documents", match_types: %w[textarea file] }
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
