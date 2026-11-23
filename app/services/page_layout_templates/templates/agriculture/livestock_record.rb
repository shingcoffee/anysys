# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Agriculture
      module LivestockRecord
        DEFINITION = {
          key: "livestock_record",
          name: "Livestock Record",
          description: "Animal health and inventory tracking with breed, weight, and veterinary notes",
          category: "agriculture",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Animal Identification" }],
            [{ type: :input, width: "half", label: "Animal ID / Ear Tag Number" }, { type: :select, width: "half", label: "Species (Cattle, Swine, Sheep, Goat, Poultry, Horse, Other)" }],
            [{ type: :input, width: "half", label: "Breed / Breed Mix" }, { type: :select, width: "half", label: "Gender (Male, Female, Castrated)" }],
            [{ type: :date, width: "half", label: "Date of Birth / Approximate Age" }, { type: :input, width: "half", label: "Sire ID (Father)" }],
            [{ type: :input, width: "half", label: "Dam ID (Mother)" }, { type: :input, width: "half", label: "Registration Number (if applicable)" }],
            [{ type: :select, width: "half", label: "Purpose (Breeding, Meat, Dairy, Show, Pet, Draft)" }, { type: :date, width: "half", label: "Acquisition Date" }],
            [{ type: :divider }],
            [{ type: :section, label: "Health Records" }],
            [{ type: :number, width: "half", label: "Current Weight (lbs)" }, { type: :date, width: "half", label: "Last Weigh Date" }],
            [{ type: :input, width: "half", label: "Body Condition Score (1-5)" }, { type: :input, width: "half", label: "Microchip / RFID Number" }],
            [{ type: :select, width: "half", label: "Current Health Status (Healthy, Sick, Injured, Under Treatment)" }, { type: :date, width: "half", label: "Last Veterinary Exam Date" }],
            [{ type: :input, width: "half", label: "Attending Veterinarian" }, { type: :input, width: "half", label: "Vet Contact Phone" }],
            [{ type: :checkbox, width: "full", label: "Vaccinations Given (Brucellosis, Clostridial 7/8-way, IBR/BVD, Rabies, Tetanus, Foot & Mouth, Other)" }],
            [{ type: :date, width: "half", label: "Last Vaccination Date" }, { type: :date, width: "half", label: "Next Vaccination Due" }],
            [{ type: :date, width: "half", label: "Last Deworming Date" }, { type: :input, width: "half", label: "Dewormer Product Used" }],
            [{ type: :textarea, width: "full", label: "Current Medications & Treatments" }],
            [{ type: :divider }],
            [{ type: :section, label: "Notes & Photos" }],
            [{ type: :input, width: "half", label: "Feed Type / Ration" }, { type: :number, width: "half", label: "Daily Feed Amount (lbs)" }],
            [{ type: :checkbox, width: "full", label: "Supplements (Minerals, Vitamins, Protein Blocks, Probiotics, Other)" }],
            [{ type: :radio, width: "full", label: "Breeding Status (Open, Bred, Confirmed Pregnant, Not Breeding)" }],
            [{ type: :date, width: "half", label: "Last Breeding Date" }, { type: :date, width: "half", label: "Expected Calving / Farrowing Date" }],
            [{ type: :textarea, width: "full", label: "Medical History, Feeding, Breeding & Veterinary Notes" }],
            [{ type: :file, width: "full", label: "Upload Animal Photos & Health Documents" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Animal Info", match_types: %w[text date select number] },
              { label: "Health Records", match_types: %w[checkbox radio] },
              { label: "Notes & Photos", match_types: %w[textarea file] }
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
