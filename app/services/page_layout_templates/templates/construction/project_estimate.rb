# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Construction
      module ProjectEstimate
        DEFINITION = {
          key: "project_estimate",
          name: "Project Estimate Request",
          description: "Construction or renovation quote request with scope and timeline",
          category: "construction",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :select, width: "half", label: "Preferred Contact Method (Phone, Email, Text)" }],
            [{ type: :input, width: "full", label: "Project Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :divider }],
            [{ type: :section, label: "Project Scope" }],
            [{ type: :select, width: "half", label: "Project Type (New Build, Renovation, Addition, Repair, Remodel)" }, { type: :select, width: "half", label: "Property Type (Residential, Commercial, Industrial)" }],
            [{ type: :select, width: "half", label: "Budget Range ($)" }, { type: :select, width: "half", label: "Desired Timeline (ASAP, 1-3 months, 3-6 months, 6-12 months)" }],
            [{ type: :number, width: "half", label: "Estimated Square Footage" }, { type: :date, width: "half", label: "Desired Start Date" }],
            [{ type: :radio, width: "full", label: "Have you obtained the required permits?" }],
            [{ type: :radio, width: "full", label: "Do you have architectural plans or drawings?" }],
            [{ type: :checkbox, width: "full", label: "Services Needed (Demo, Framing, Roofing, Electrical, Plumbing, HVAC, Drywall, Flooring, Painting, Tiling, Permits, Other)" }],
            [{ type: :textarea, width: "full", label: "Detailed Project Description & Scope of Work" }],
            [{ type: :file, width: "full", label: "Upload Plans, Drawings, or Reference Photos" }],
            [{ type: :select, width: "half", label: "How Did You Hear About Us?" }, { type: :radio, width: "half", label: "Have you worked with us before?" }]
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
              "file" => "full"
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Project Scope", match_types: %w[select number date radio] },
              { label: "Details & Attachments", match_types: %w[checkbox textarea file] }
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
