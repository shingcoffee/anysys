# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Library
      module ArchiveRequest
        DEFINITION = {
          key: "archive_research_request",
          name: "Archive Research Request",
          description: "Special collections and archive research request with topic, time period, and material type preferences",
          category: "library",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Researcher Information" }],
            [{ type: :input, width: "half", label: "Researcher Full Name" }, { type: :input, width: "half", label: "Affiliation / Institution" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :select, width: "half", label: "Researcher Role (Academic, Journalist, Genealogist, Independent, Other)" }, { type: :input, width: "half", label: "Library Card / ID Number (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Research Details" }],
            [{ type: :input, width: "full", label: "Research Topic / Subject" }],
            [{ type: :select, width: "half", label: "Time Period / Era" }, { type: :select, width: "half", label: "Collection Area / Subject Domain" }],
            [{ type: :checkbox, width: "full", label: "Material Types of Interest (Manuscripts, Photographs, Maps, Newspapers, Oral Histories, Government Records, Books, Microfilm)" }],
            [{ type: :select, width: "half", label: "Purpose of Research" }, { type: :radio, width: "half", label: "Will this research be published?" }],
            [{ type: :textarea, width: "full", label: "Detailed Description of What You Are Looking For" }],
            [{ type: :divider }],
            [{ type: :section, label: "Visit Preferences" }],
            [{ type: :date, width: "half", label: "Preferred Visit Date" }, { type: :select, width: "half", label: "Expected Visit Duration" }],
            [{ type: :radio, width: "full", label: "Is this your first visit to our archives?" }],
            [{ type: :radio, width: "full", label: "Do you need reproduction or scanning services?" }],
            [{ type: :textarea, width: "full", label: "Additional Notes or Specific Item Requests" }]
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
              "textarea" => "full"
            },
            sections: [
              { label: "Researcher Info", match_types: %w[text email tel] },
              { label: "Research & Visit Details", match_types: %w[select date checkbox radio] },
              { label: "Description & Notes", match_types: %w[textarea] }
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
