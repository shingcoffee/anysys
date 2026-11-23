# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Creator
      module SponsorshipApplication
        DEFINITION = {
          key: "sponsorship_application",
          name: "Sponsorship Application",
          description: "Event or content sponsorship application with brand details, sponsorship tiers, and deliverables",
          category: "creator",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Brand Information" }],
            [{ type: :input, width: "half", label: "Company / Brand Name" }, { type: :input, width: "half", label: "Contact Person" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Website URL" }, { type: :select, width: "half", label: "Industry" }],
            [{ type: :input, width: "half", label: "Company Size (employees)" }, { type: :select, width: "half", label: "Country" }],
            [{ type: :divider }],
            [{ type: :section, label: "Sponsorship Details" }],
            [{ type: :select, width: "half", label: "Sponsorship Tier (Title, Gold, Silver, Bronze, Custom)" }, { type: :select, width: "half", label: "Budget Range" }],
            [{ type: :select, width: "half", label: "Event / Content Being Sponsored" }, { type: :date, width: "half", label: "Campaign / Event Date" }],
            [{ type: :checkbox, width: "full", label: "Desired Exposure (Logo Placement, Mentions, Social Posts, Email, Stage Time, Booth Space, Digital Ads)" }],
            [{ type: :select, width: "half", label: "Target Audience Demographic" }, { type: :select, width: "half", label: "Geographic Reach" }],
            [{ type: :radio, width: "full", label: "Have you sponsored with us previously?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Goals & Materials" }],
            [{ type: :textarea, width: "full", label: "Sponsorship Goals and Objectives" }],
            [{ type: :textarea, width: "full", label: "Target Audience Alignment / Why This Partnership?" }],
            [{ type: :textarea, width: "full", label: "Any specific requirements or special requests?" }],
            [{ type: :file, width: "full", label: "Brand Guidelines / Logo Package" }],
            [{ type: :checkbox, width: "full", label: "I confirm our brand aligns with the event/content values and terms" }]
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
              "file" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Brand Info", match_types: %w[text email tel url] },
              { label: "Sponsorship Details", match_types: %w[select date checkbox radio] },
              { label: "Goals & Materials", match_types: %w[textarea file] }
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
