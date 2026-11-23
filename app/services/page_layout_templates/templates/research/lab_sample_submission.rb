# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Research
      module LabSampleSubmission
        DEFINITION = {
          key: "lab_sample_submission",
          name: "Lab Sample Submission",
          description: "Laboratory sample submission with specimen details, testing requirements, and chain of custody",
          category: "research",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Submitter Information" }],
            [{ type: :input, width: "half", label: "Submitter Name" }, { type: :input, width: "half", label: "Organization / Institution" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Principal Investigator (if applicable)" }, { type: :input, width: "half", label: "Project / Study ID" }],
            [{ type: :divider }],
            [{ type: :section, label: "Sample Details" }],
            [{ type: :input, width: "half", label: "Sample ID / Barcode" }, { type: :select, width: "half", label: "Sample Type (Blood, Urine, Tissue, Soil, Water, Air, Other)" }],
            [{ type: :date, width: "half", label: "Collection Date" }, { type: :input, width: "half", label: "Collection Site / Location" }],
            [{ type: :select, width: "half", label: "Storage Condition (Room Temp, Refrigerated, Frozen, Dry Ice)" }, { type: :number, width: "half", label: "Number of Samples / Replicates" }],
            [{ type: :input, width: "half", label: "Sample Volume / Weight" }, { type: :select, width: "half", label: "Container Type (Tube, Vial, Swab, Bag, Other)" }],
            [{ type: :radio, width: "full", label: "Are samples potentially hazardous or infectious?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Testing & Instructions" }],
            [{ type: :checkbox, width: "full", label: "Tests Requested (PCR, Culture, Toxicology, Pathology, Chemical Analysis, Genomics, Microscopy, Other)" }],
            [{ type: :select, width: "half", label: "Priority Level (Routine, Urgent, STAT)" }, { type: :select, width: "half", label: "Turnaround Time (Standard, Expedited, 24-Hour)" }],
            [{ type: :select, width: "half", label: "Report Delivery Method (Email, Portal, Fax)" }, { type: :input, width: "half", label: "PO Number / Billing Code" }],
            [{ type: :textarea, width: "full", label: "Special Handling Instructions or Notes" }],
            [{ type: :file, width: "full", label: "Upload Chain of Custody Form or Supporting Documents" }],
            [{ type: :checkbox, width: "full", label: "I confirm samples are properly labeled, handled, and comply with biosafety protocols" }]
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
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Submitter Info", match_types: %w[text email tel] },
              { label: "Sample & Testing", match_types: %w[date select number radio] },
              { label: "Instructions & Confirmation", match_types: %w[checkbox textarea file] }
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
