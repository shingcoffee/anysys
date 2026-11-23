# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Cleaning
      module CleaningQuote
        DEFINITION = {
          key: "cleaning_quote",
          name: "Cleaning Service Quote",
          description: "Residential or commercial cleaning estimate with rooms, frequency, and extras",
          category: "cleaning",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :input, width: "full", label: "Service Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "third", label: "State" }, { type: :input, width: "third", label: "ZIP Code" }],
            [{ type: :divider }],
            [{ type: :section, label: "Property & Service Details" }],
            [{ type: :select, width: "half", label: "Property Type (Home, Apartment, Condo, Office, Commercial, Other)" }, { type: :number, width: "half", label: "Square Footage (approx.)" }],
            [{ type: :number, width: "half", label: "Number of Bedrooms" }, { type: :number, width: "half", label: "Number of Bathrooms" }],
            [{ type: :number, width: "half", label: "Number of Floors / Stories" }, { type: :radio, width: "half", label: "Furnished or Empty?" }],
            [{ type: :select, width: "full", label: "Cleaning Type (Standard, Deep Clean, Move-In/Out, Post-Construction, One-Time, Recurring)" }],
            [{ type: :select, width: "half", label: "Frequency (One-Time, Weekly, Bi-Weekly, Monthly)" }, { type: :select, width: "half", label: "Preferred Day of Week" }],
            [{ type: :select, width: "half", label: "Preferred Time Window" }, { type: :date, width: "half", label: "Desired Start Date" }],
            [{ type: :radio, width: "full", label: "Will you provide cleaning supplies or should we bring ours?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Extras & Notes" }],
            [{ type: :checkbox, width: "full", label: "Add-On Services (Inside Windows, Inside Oven, Inside Refrigerator, Laundry, Dishes, Carpet Cleaning, Upholstery, Organizing, Garage, Patio/Deck)" }],
            [{ type: :radio, width: "full", label: "Do you have pets?" }],
            [{ type: :select, width: "half", label: "Type of Pet(s)" }, { type: :number, width: "half", label: "Number of Pets" }],
            [{ type: :textarea, width: "full", label: "Special Instructions, Problem Areas, or Preferences" }],
            [{ type: :select, width: "half", label: "Budget Range" }, { type: :select, width: "half", label: "Preferred Contact Method" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "number" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Property & Service Details", match_types: %w[select number date radio] },
              { label: "Extras & Notes", match_types: %w[checkbox textarea] }
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
