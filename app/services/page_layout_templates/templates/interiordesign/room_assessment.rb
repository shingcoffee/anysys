# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Interiordesign
      module RoomAssessment
        DEFINITION = {
          key: "room_design_assessment",
          name: "Room Design Assessment",
          description: "Detailed room assessment for design consultation with dimensions, existing furniture, and goals",
          category: "interiordesign",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Client Information" }],
            [{ type: :input, width: "half", label: "Client Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "full", label: "Property Address" }],
            [{ type: :select, width: "half", label: "Property Type (House, Condo, Apartment, Office)" }, { type: :select, width: "half", label: "Budget Range" }],
            [{ type: :divider }],
            [{ type: :section, label: "Room Details" }],
            [{ type: :select, width: "half", label: "Room Type" }, { type: :select, width: "half", label: "Current Style" }],
            [{ type: :input, width: "third", label: "Length (ft)" }, { type: :input, width: "third", label: "Width (ft)" }, { type: :input, width: "third", label: "Ceiling Height (ft)" }],
            [{ type: :select, width: "half", label: "Natural Light Level (None, Low, Moderate, Abundant)" }, { type: :select, width: "half", label: "Floor Type (Hardwood, Tile, Carpet, Concrete, Other)" }],
            [{ type: :select, width: "half", label: "Wall Color / Finish (keep or change?)" }, { type: :select, width: "half", label: "Primary Use (Relaxing, Working, Entertaining, Sleeping)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Design Goals" }],
            [{ type: :checkbox, width: "full", label: "What Needs to Change? (Furniture, Lighting, Color, Layout, Storage, Flooring, Window Treatments, All)" }],
            [{ type: :radio, width: "full", label: "Keep any existing furniture or decor?" }],
            [{ type: :textarea, width: "full", label: "Functional requirements (e.g., storage, seating for 8, home office)" }],
            [{ type: :textarea, width: "full", label: "Things you love / must-haves" }],
            [{ type: :textarea, width: "full", label: "Things you dislike or want to avoid" }],
            [{ type: :file, width: "full", label: "Current Room Photos" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "third",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Client & Property", match_types: %w[email tel] },
              { label: "Room Specs", match_types: %w[text select] },
              { label: "Design Brief", match_types: %w[checkbox radio textarea file] }
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
