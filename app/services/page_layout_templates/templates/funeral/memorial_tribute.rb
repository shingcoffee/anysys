# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Funeral
      module MemorialTribute
        DEFINITION = {
          key: "memorial_tribute",
          name: "Memorial Tribute Submission",
          description: "Online memorial tribute page for sharing memories, photos, and condolences in honor of a loved one",
          category: "funeral",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Your Information" }],
            [{ type: :input, width: "half", label: "Your Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone (optional)" }, { type: :select, width: "half", label: "Relationship to Deceased" }],
            [{ type: :divider }],
            [{ type: :section, label: "In Memory Of" }],
            [{ type: :input, width: "half", label: "Name of Loved One" }, { type: :date, width: "half", label: "Date of Passing" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Tribute" }],
            [{ type: :select, width: "half", label: "Tribute Type (Condolence, Memory, Poem, Prayer, Quote, Story)" }, { type: :input, width: "half", label: "Title for Your Tribute" }],
            [{ type: :textarea, width: "full", label: "Share your favorite memory, message, or condolence" }],
            [{ type: :textarea, width: "full", label: "A special quality or impact they had on your life (optional)" }],
            [{ type: :input, width: "half", label: "Candle / Flower Dedication Message (optional)" }, { type: :select, width: "half", label: "Virtual Token (Candle, Flower, Dove, Star)" }],
            [{ type: :file, width: "full", label: "Photos or Short Videos (optional)" }],
            [{ type: :radio, width: "full", label: "May we share this tribute publicly on the memorial page?" }],
            [{ type: :checkbox, width: "full", label: "Notify me of other tributes and updates about this memorial" }]
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
              { label: "Your Information", match_types: %w[text email tel] },
              { label: "Tribute Details", match_types: %w[date select radio checkbox] },
              { label: "Memory & Media", match_types: %w[textarea file] }
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
