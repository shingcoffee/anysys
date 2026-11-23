# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Funeral
      module ServiceArrangement
        DEFINITION = {
          key: "funeral_service_arrangement",
          name: "Funeral Service Arrangement",
          description: "Funeral and memorial service planning with deceased information, service preferences, and family contact details",
          category: "funeral",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Contact Person" }],
            [{ type: :input, width: "half", label: "Your Full Name" }, { type: :select, width: "half", label: "Relationship to Deceased" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "full", label: "Mailing Address" }],
            [{ type: :input, width: "half", label: "Secondary Contact Name" }, { type: :input, width: "half", label: "Secondary Contact Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Deceased Information" }],
            [{ type: :input, width: "half", label: "Full Legal Name" }, { type: :input, width: "half", label: "Preferred / Known As" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :date, width: "half", label: "Date of Passing" }],
            [{ type: :input, width: "half", label: "Place of Birth" }, { type: :input, width: "half", label: "Place of Passing" }],
            [{ type: :select, width: "half", label: "Religion / Faith Tradition" }, { type: :select, width: "half", label: "Ethnicity / Cultural Background" }],
            [{ type: :divider }],
            [{ type: :section, label: "Service Preferences" }],
            [{ type: :select, width: "half", label: "Service Type (Funeral, Memorial, Graveside, Celebration of Life, Private)" }, { type: :select, width: "half", label: "Disposition (Burial, Cremation, Donation to Science)" }],
            [{ type: :date, width: "half", label: "Preferred Service Date" }, { type: :select, width: "half", label: "Preferred Time of Day" }],
            [{ type: :radio, width: "full", label: "Will there be a Visitation / Viewing?" }],
            [{ type: :checkbox, width: "full", label: "Additional Services Needed (Obituary, Flowers, Reception, Live Stream, Military Honors, Urn/Casket)" }],
            [{ type: :textarea, width: "full", label: "Special Requests or Cultural / Religious Considerations" }],
            [{ type: :textarea, width: "full", label: "Life Highlights for Obituary" }],
            [{ type: :file, width: "full", label: "Photo of Deceased (for memorial materials)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact Person", match_types: %w[text email tel] },
              { label: "Deceased & Service Details", match_types: %w[date select radio checkbox] },
              { label: "Notes & Obituary", match_types: %w[textarea file] }
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
