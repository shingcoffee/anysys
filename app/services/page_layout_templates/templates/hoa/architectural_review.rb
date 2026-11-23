# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hoa
      module ArchitecturalReview
        DEFINITION = {
          key: "architectural_review",
          name: "Architectural Review Request",
          description: "HOA architectural review for exterior modifications with plans, materials, and timeline",
          category: "hoa",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Homeowner Information" }],
            [{ type: :input, width: "half", label: "Homeowner Full Name" }, { type: :input, width: "half", label: "Unit / Lot Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Property Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Modification Details" }],
            [{ type: :select, width: "half", label: "Modification Type (Fence, Deck, Patio, Landscaping, Paint, Addition, Driveway, Other)" }, { type: :select, width: "half", label: "Scope (Minor, Major, Structural)" }],
            [{ type: :textarea, width: "full", label: "Description of Proposed Changes" }],
            [{ type: :input, width: "half", label: "Materials to be Used" }, { type: :input, width: "half", label: "Colors / Finishes" }],
            [{ type: :date, width: "half", label: "Estimated Start Date" }, { type: :date, width: "half", label: "Estimated Completion Date" }],
            [{ type: :number, width: "half", label: "Estimated Cost ($)" }, { type: :radio, width: "half", label: "Permit Required? (check with local municipality)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Contractor & Documents" }],
            [{ type: :input, width: "half", label: "Contractor Name" }, { type: :input, width: "half", label: "Contractor License Number" }],
            [{ type: :input, width: "half", label: "Contractor Phone" }, { type: :input, width: "half", label: "Contractor Insurance Expiry" }],
            [{ type: :file, width: "full", label: "Plans, Drawings, or Photos of Proposed Work" }],
            [{ type: :checkbox, width: "full", label: "I have reviewed the HOA design guidelines and this proposal complies" }],
            [{ type: :checkbox, width: "full", label: "I agree to restore the property if changes are not approved" }]
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
              "textarea" => "full",
              "file" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Homeowner Info", match_types: %w[text email tel] },
              { label: "Modification Details", match_types: %w[select date number radio textarea] },
              { label: "Documents & Agreement", match_types: %w[file checkbox] }
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
