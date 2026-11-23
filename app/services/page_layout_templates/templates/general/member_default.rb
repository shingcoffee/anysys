# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module General
      module MemberDefault
        DEFINITION = {
          key: "member_default",
          name: "Default (Member)",
          description: "Member-facing layout — mobile-first widths, groups attributes by the entity's curated attribute groups, hides anything not flagged visible to members.",
          category: "general",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Account" }],
            [{ type: :input, width: "full" }],
            [{ type: :input, width: "half" }, { type: :input, width: "half" }],
            [{ type: :divider }],
            [{ type: :section, label: "Profile" }],
            [{ type: :select, width: "full" }],
            [{ type: :textarea, width: "full" }]
          ],
          layout: {
            audience: "member",
            default_width: "full",
            field_width_rules: {
              "text" => "half", "search" => "full", "password" => "full", "hidden" => "half",
              "select" => "full", "multi-select" => "full",
              "radio" => "full", "checkbox" => "full", "switch" => "full",
              "number" => "half", "currency" => "half", "range" => "full", "rating" => "full",
              "date" => "half", "time" => "half", "datetime-local" => "full",
              "month" => "half", "week" => "half",
              "email" => "full", "tel" => "half", "url" => "full",
              "rich-text" => "full", "signature" => "full",
              "file" => "full", "image" => "full",
              "color" => "half", "textarea" => "full"
            },
            group_by: :attribute_groups,
            sections: [],
            inject_elements: []
          }.freeze
        }.freeze
      end
    end
  end
end
