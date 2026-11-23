# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Beauty
      module SalonAppointment
        DEFINITION = {
          key: "salon_appointment",
          name: "Salon Appointment",
          description: "Hair or beauty salon booking with service selection and stylist preference",
          category: "beauty",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Contact Info" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :radio, width: "full", label: "Are you a new or returning client?" }],
            [{ type: :select, width: "half", label: "How Did You Hear About Us?" }, { type: :input, width: "half", label: "Referred By (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Appointment Details" }],
            [{ type: :date, width: "half", label: "Preferred Date" }, { type: :select, width: "half", label: "Preferred Time Slot" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time Slot" }],
            [{ type: :select, width: "half", label: "Preferred Stylist / Technician" }, { type: :select, width: "half", label: "Location / Salon Branch" }],
            [{ type: :checkbox, width: "full", label: "Services Requested (Haircut, Hair Color, Highlights, Balayage, Root Touch-Up, Blowout, Treatment, Extensions, Perm, Updo, Makeup, Manicure, Pedicure, Facial, Waxing)" }],
            [{ type: :textarea, width: "full", label: "Detailed Service Description & Style Preferences" }],
            [{ type: :select, width: "half", label: "Hair Texture (Straight, Wavy, Curly, Coily)" }, { type: :select, width: "half", label: "Hair Thickness (Fine, Medium, Thick)" }],
            [{ type: :select, width: "half", label: "Hair Length (Short, Medium, Long)" }, { type: :select, width: "half", label: "Scalp Condition (Normal, Oily, Dry, Sensitive)" }],
            [{ type: :radio, width: "full", label: "Have you had chemical treatments in the last 6 months?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Notes & Inspiration" }],
            [{ type: :textarea, width: "full", label: "Known Allergies to Hair Products, Dyes, or Chemicals" }],
            [{ type: :radio, width: "full", label: "Are you currently pregnant or nursing?" }],
            [{ type: :file, width: "full", label: "Upload Inspiration Photos / Reference Images (optional)" }],
            [{ type: :textarea, width: "full", label: "Special Requests, Concerns, or Notes for Your Stylist" }],
            [{ type: :checkbox, width: "full", label: "I agree to the cancellation policy (24-hour notice required)" }]
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
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel radio] },
              { label: "Appointment Details", match_types: %w[checkbox select date time] },
              { label: "Notes & Inspiration", match_types: %w[textarea file] }
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
