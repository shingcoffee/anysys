# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Survey
      module MarketResearch
        DEFINITION = {
          key: "market_research",
          name: "Market Research",
          description: "Consumer research with demographics, preferences, and product feedback",
          category: "survey",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Respondent Demographics" }],
            [{ type: :select, width: "half", label: "Age Range" }, { type: :select, width: "half", label: "Gender" }],
            [{ type: :select, width: "half", label: "Annual Household Income" }, { type: :select, width: "half", label: "Education Level" }],
            [{ type: :select, width: "half", label: "Region / Country" }, { type: :select, width: "half", label: "Employment Status" }],
            [{ type: :select, width: "half", label: "Household Size" }, { type: :select, width: "half", label: "Homeownership Status" }],
            [{ type: :divider }],
            [{ type: :section, label: "Product / Service Feedback" }],
            [{ type: :select, width: "half", label: "How familiar are you with our brand?" }, { type: :select, width: "half", label: "How often do you purchase in this category?" }],
            [{ type: :select, width: "half", label: "Overall Impression (1-5)" }, { type: :select, width: "half", label: "Likelihood to Purchase (1-10)" }],
            [{ type: :checkbox, width: "full", label: "Which features are most important to you? (Price, Quality, Convenience, Brand, Sustainability, Support)" }],
            [{ type: :radio, width: "full", label: "How do you primarily purchase products in this category? (Online, In-Store, Both, Other)" }],
            [{ type: :radio, width: "full", label: "How likely are you to recommend this product to others?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Open Feedback" }],
            [{ type: :textarea, width: "full", label: "What do you like about the product / service?" }],
            [{ type: :textarea, width: "full", label: "What improvements would you suggest?" }],
            [{ type: :textarea, width: "full", label: "Any other comments or observations?" }],
            [{ type: :checkbox, width: "full", label: "I am willing to be contacted for a follow-up interview (optional)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "range" => "full",
            },
            sections: [
              { label: "Demographics", match_types: %w[select] },
              { label: "Product Feedback", match_types: %w[radio checkbox range] },
              { label: "Open Feedback", match_types: %w[textarea] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
