# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Pets
      module VetAppointment
        DEFINITION = {
          key: "vet_appointment",
          name: "Veterinary Appointment",
          description: "Pet health visit booking with symptoms, medical history, and vaccination",
          category: "pets",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Owner Information" }],
            [{ type: :input, width: "half", label: "Owner Name" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :input, width: "half", label: "Email" }, { type: :input, width: "half", label: "Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Pet Information" }],
            [{ type: :input, width: "half", label: "Pet Name" }, { type: :select, width: "half", label: "Species (Dog, Cat, Bird, Rabbit, Reptile, Other)" }],
            [{ type: :input, width: "half", label: "Breed" }, { type: :select, width: "half", label: "Sex (Male, Female, Unknown)" }],
            [{ type: :number, width: "half", label: "Age (Years)" }, { type: :number, width: "half", label: "Weight (lbs/kg)" }],
            [{ type: :radio, width: "full", label: "Spayed / Neutered?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Visit Details" }],
            [{ type: :select, width: "half", label: "Reason for Visit (Wellness, Illness, Vaccination, Surgery, Emergency, Follow-up)" }, { type: :date, width: "half", label: "Preferred Date" }],
            [{ type: :select, width: "half", label: "Preferred Time" }, { type: :date, width: "half", label: "Alternate Date" }],
            [{ type: :textarea, width: "full", label: "Symptoms or Concerns" }],
            [{ type: :checkbox, width: "full", label: "Vaccinations: Rabies, DHPP, Bordetella, Feline FVRCP, FeLV, Heartworm Prevention" }],
            [{ type: :radio, width: "full", label: "Is this your pet's first visit with us?" }],
            [{ type: :input, width: "half", label: "Previous Vet Name (if applicable)" }, { type: :file, width: "half", label: "Medical Records (if transferring)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "half"
            },
            sections: [
              { label: "Owner Details", match_types: %w[text email tel] },
              { label: "Pet Details", match_types: %w[select number radio] },
              { label: "Visit Info", match_types: %w[date checkbox textarea file] }
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
