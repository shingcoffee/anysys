# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Manufacturing
      module QualityInspection
        DEFINITION = {
          key: "quality_inspection",
          name: "Quality Inspection",
          description: "Product quality check with pass/fail criteria, measurements, and defect tracking",
          category: "manufacturing",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Product & Batch Info" }],
            [{ type: :input, width: "half", label: "Inspector Name" }, { type: :date, width: "half", label: "Inspection Date" }],
            [{ type: :input, width: "half", label: "Product / Part Number" }, { type: :input, width: "half", label: "Batch / Lot Number" }],
            [{ type: :select, width: "half", label: "Production Line / Shift (Day, Evening, Night)" }, { type: :number, width: "half", label: "Sample Size" }],
            [{ type: :select, width: "half", label: "Inspection Type (Incoming, In-Process, Final, Audit, Receiving)" }, { type: :input, width: "half", label: "Work Order / Job #" }],
            [{ type: :input, width: "half", label: "Supplier / Vendor (for incoming)" }, { type: :select, width: "half", label: "Customer / End Market" }],
            [{ type: :divider }],
            [{ type: :section, label: "Inspection Checklist" }],
            [{ type: :select, width: "half", label: "Visual Appearance (Pass, Fail, N/A)" }, { type: :select, width: "half", label: "Dimensions / Measurements (Pass, Fail, N/A)" }],
            [{ type: :select, width: "half", label: "Weight (Pass, Fail, N/A)" }, { type: :select, width: "half", label: "Material / Composition (Pass, Fail, N/A)" }],
            [{ type: :select, width: "half", label: "Functionality / Performance (Pass, Fail, N/A)" }, { type: :select, width: "half", label: "Safety Compliance (Pass, Fail, N/A)" }],
            [{ type: :select, width: "half", label: "Packaging Integrity (Pass, Fail, N/A)" }, { type: :select, width: "half", label: "Labeling & Marking (Pass, Fail, N/A)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Results & Photos" }],
            [{ type: :number, width: "half", label: "Number of Defects Found" }, { type: :select, width: "half", label: "Overall Result (Pass, Fail, Conditional Pass, Hold)" }],
            [{ type: :textarea, width: "full", label: "Defect Details & Observations" }],
            [{ type: :textarea, width: "full", label: "Corrective Actions Recommended" }],
            [{ type: :file, width: "full", label: "Upload Inspection Photos or Measurement Records" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Product & Batch Info", match_types: %w[text date select number] },
              { label: "Inspection Checklist", match_types: %w[] },
              { label: "Results & Photos", match_types: %w[textarea file] }
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
