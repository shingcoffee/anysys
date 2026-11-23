# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Agriculture
      module CropReport
        DEFINITION = {
          key: "crop_report",
          name: "Crop Report",
          description: "Field crop status report with yield estimates, conditions, and photos",
          category: "agriculture",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Farm & Field Information" }],
            [{ type: :input, width: "half", label: "Farm Name / Operator" }, { type: :input, width: "half", label: "Field Name / Plot ID" }],
            [{ type: :date, width: "half", label: "Report Date" }, { type: :input, width: "half", label: "Reporter Name" }],
            [{ type: :number, width: "half", label: "Field Size (Acres)" }, { type: :input, width: "half", label: "GPS Coordinates (optional)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Crop Details" }],
            [{ type: :select, width: "half", label: "Crop Type (Corn, Soybeans, Wheat, Cotton, Rice, Sorghum, Other)" }, { type: :input, width: "half", label: "Crop Variety / Hybrid" }],
            [{ type: :date, width: "half", label: "Planting Date" }, { type: :date, width: "half", label: "Expected Harvest Date" }],
            [{ type: :select, width: "half", label: "Growth Stage" }, { type: :select, width: "half", label: "Overall Condition (Excellent, Good, Fair, Poor)" }],
            [{ type: :number, width: "half", label: "Estimated Yield (bushels/acre)" }, { type: :number, width: "half", label: "Current Market Price ($/bushel)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Observations & Photos" }],
            [{ type: :select, width: "half", label: "Soil Type" }, { type: :select, width: "half", label: "Soil Moisture Level (Dry, Adequate, Wet, Saturated)" }],
            [{ type: :input, width: "half", label: "Fertilizer Applied (Type)" }, { type: :number, width: "half", label: "Application Rate (lbs/acre)" }],
            [{ type: :select, width: "half", label: "Irrigation Method (Drip, Sprinkler, Flood, None)" }, { type: :number, width: "half", label: "Total Water Applied (inches)" }],
            [{ type: :input, width: "half", label: "Herbicide Used" }, { type: :input, width: "half", label: "Pesticide / Fungicide Used" }],
            [{ type: :checkbox, width: "full", label: "Issues Observed (Drought Stress, Flooding, Pest Damage, Disease, Weed Pressure, Hail, Wind, Wildlife, Nutrient Deficiency, Equipment Issues)" }],
            [{ type: :textarea, width: "full", label: "Weather Conditions & Growing Season Notes" }],
            [{ type: :textarea, width: "full", label: "Recommended Actions / Management Plans" }],
            [{ type: :file, width: "full", label: "Upload Field Photos & Crop Images" }],
            [{ type: :checkbox, width: "full", label: "I certify the information in this report is accurate to the best of my knowledge" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Farm & Field", match_types: %w[text email date number] },
              { label: "Crop Details", match_types: %w[select range] },
              { label: "Observations & Photos", match_types: %w[checkbox textarea file radio] }
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
