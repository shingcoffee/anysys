# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Creative
      module DesignBrief
        DEFINITION = {
          key: "design_brief",
          name: "Design Brief",
          description: "Creative project brief with brand guidelines, deliverables, and timeline",
          category: "creative",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Client & Contact" }],
            [{ type: :input, width: "half", label: "Company Name" }, { type: :input, width: "half", label: "Contact Person" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Website" }, { type: :select, width: "half", label: "Industry" }],
            [{ type: :select, width: "half", label: "Company Size" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Project Scope" }],
            [{ type: :select, width: "half", label: "Project Type (Logo, Brand Identity, Website, Print, Social Media, Packaging, Other)" }, { type: :select, width: "half", label: "Budget Range" }],
            [{ type: :date, width: "half", label: "Project Deadline" }, { type: :select, width: "half", label: "Priority (Standard, Urgent, Rush)" }],
            [{ type: :checkbox, width: "full", label: "Deliverables Needed (Logo, Color Palette, Typography, Brand Guide, Business Cards, Social Templates, Print Files, Web Assets)" }],
            [{ type: :textarea, width: "full", label: "Project Description & Goals" }],
            [{ type: :textarea, width: "full", label: "Target Audience Description" }],
            [{ type: :divider }],
            [{ type: :section, label: "Creative Direction" }],
            [{ type: :select, width: "half", label: "Tone / Mood (Professional, Playful, Minimalist, Bold, Luxurious, Friendly)" }, { type: :radio, width: "half", label: "Do you have an existing brand?" }],
            [{ type: :textarea, width: "full", label: "Brand Guidelines / Existing Style Notes" }],
            [{ type: :textarea, width: "full", label: "Competitors or Brands You Admire / Want to Differentiate From" }],
            [{ type: :input, width: "half", label: "Preferred Color(s)" }, { type: :input, width: "half", label: "Fonts to Avoid or Include" }],
            [{ type: :file, width: "full", label: "Upload Reference Files (Logos, Images, Existing Assets)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Client & Contact", match_types: %w[text email tel url] },
              { label: "Project Scope", match_types: %w[select date checkbox] },
              { label: "Creative Direction", match_types: %w[textarea radio file] }
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
