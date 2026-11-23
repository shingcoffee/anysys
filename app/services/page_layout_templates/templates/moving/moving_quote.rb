# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Moving
      module MovingQuote
        DEFINITION = {
          key: "moving_quote",
          name: "Moving Quote",
          description: "Residential or commercial moving estimate with inventory and special items",
          category: "moving",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :input, width: "half", label: "Email" }, { type: :select, width: "half", label: "Move Type (Residential, Commercial, Local, Long Distance, International)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Move Details" }],
            [{ type: :input, width: "full", label: "Moving From (Full Address)" }],
            [{ type: :input, width: "full", label: "Moving To (Full Address)" }],
            [{ type: :date, width: "half", label: "Preferred Move Date" }, { type: :date, width: "half", label: "Alternate Date" }],
            [{ type: :select, width: "half", label: "Home / Office Size" }, { type: :number, width: "half", label: "Floors / Stairs (From)" }],
            [{ type: :number, width: "half", label: "Floors / Stairs (To)" }, { type: :radio, width: "half", label: "Elevator Available?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Inventory & Services" }],
            [{ type: :checkbox, width: "full", label: "Large Items: Sofa, Bed (King, Queen), Dining Table, Piano, Pool Table, Safe, Exercise Equipment" }],
            [{ type: :radio, width: "full", label: "Need packing services?" }],
            [{ type: :radio, width: "full", label: "Need storage (short or long term)?" }],
            [{ type: :radio, width: "full", label: "Need packing materials (boxes, tape, bubble wrap)?" }],
            [{ type: :textarea, width: "full", label: "Special or Fragile Items (art, antiques, piano, electronics, etc.)" }],
            [{ type: :textarea, width: "full", label: "Additional Notes or Requests" }]
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
              "checkbox" => "full",
              "textarea" => "full"
            },
            sections: [
              { label: "Contact & Move Type", match_types: %w[text email tel select] },
              { label: "Move Details", match_types: %w[date number radio] },
              { label: "Inventory & Services", match_types: %w[checkbox textarea] }
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
