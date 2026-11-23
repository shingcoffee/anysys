# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Pets
      module PetAdoption
        DEFINITION = {
          key: "pet_adoption",
          name: "Pet Adoption Application",
          description: "Adoption request with home environment, experience, and references",
          category: "pets",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "About You" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :input, width: "half", label: "Employer / Occupation" }, { type: :input, width: "half", label: "Hours at Home per Day" }],
            [{ type: :divider }],
            [{ type: :section, label: "Home & Lifestyle" }],
            [{ type: :select, width: "half", label: "Housing Type (House, Apartment, Condo, Other)" }, { type: :radio, width: "half", label: "Do you own or rent?" }],
            [{ type: :radio, width: "full", label: "Do you have a fenced yard?" }],
            [{ type: :number, width: "half", label: "People in Household" }, { type: :number, width: "half", label: "Children Under 12?" }],
            [{ type: :number, width: "half", label: "Current Pets (count)" }, { type: :textarea, width: "half", label: "Current Pet Types & Ages" }],
            [{ type: :radio, width: "full", label: "Landlord permission for pets (if renting)?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Adoption Details" }],
            [{ type: :select, width: "half", label: "Pet Type Preference (Dog, Cat, Other)" }, { type: :select, width: "half", label: "Age Preference (Puppy/Kitten, Young Adult, Senior)" }],
            [{ type: :select, width: "half", label: "Size Preference (Small, Medium, Large, No preference)" }, { type: :select, width: "half", label: "Activity Level Preference" }],
            [{ type: :textarea, width: "full", label: "Why do you want to adopt?" }],
            [{ type: :textarea, width: "full", label: "Previous pet care experience" }],
            [{ type: :input, width: "half", label: "Reference 1 (Name & Phone)" }, { type: :input, width: "half", label: "Reference 2 (Name & Phone)" }],
            [{ type: :checkbox, width: "full", label: "I agree to a home visit and understand adoption may be denied" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Applicant & Home Info", match_types: %w[text email tel date select number radio] },
              { label: "Adoption Details", match_types: %w[textarea] },
              { label: "Agreement", match_types: %w[checkbox] }
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
