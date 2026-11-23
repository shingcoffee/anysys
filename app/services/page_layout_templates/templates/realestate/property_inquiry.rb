# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Realestate
      module PropertyInquiry
        DEFINITION = {
          key: "property_inquiry",
          name: "Property Inquiry",
          description: "Real estate listing inquiry with viewing request and budget range",
          category: "realestate",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Property Interest" }],
            [{ type: :input, width: "full", label: "Property Address / Listing ID" }],
            [{ type: :select, width: "half", label: "Property Type (House, Condo, Townhouse, Land, Commercial, Multi-family)" }, { type: :select, width: "half", label: "Transaction Type (Buy, Rent, Lease)" }],
            [{ type: :number, width: "half", label: "Max Budget ($)" }, { type: :number, width: "half", label: "Bedrooms Needed" }],
            [{ type: :divider }],
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone" }],
            [{ type: :input, width: "full", label: "Email" }],
            [{ type: :select, width: "half", label: "Best Time to Contact" }, { type: :select, width: "half", label: "Preferred Contact Method" }],
            [{ type: :divider }],
            [{ type: :section, label: "Viewing Request" }],
            [{ type: :date, width: "half", label: "Preferred Viewing Date" }, { type: :select, width: "half", label: "Preferred Time" }],
            [{ type: :date, width: "half", label: "Alternate Viewing Date" }, { type: :select, width: "half", label: "Alternate Time" }],
            [{ type: :radio, width: "full", label: "Are you pre-approved for financing?" }],
            [{ type: :textarea, width: "full", label: "Questions or Additional Requirements" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "full",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "textarea" => "full",
              "url" => "half",
              "time" => "half",
            },
            sections: [
              { label: "Property Details", match_types: %w[text select number] },
              { label: "Contact Info", match_types: %w[email tel] },
              { label: "Viewing & Notes", match_types: %w[date radio textarea time datetime-local] }
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
