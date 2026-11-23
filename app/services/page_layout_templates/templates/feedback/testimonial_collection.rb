# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Feedback
      module TestimonialCollection
        DEFINITION = {
          key: "testimonial_collection",
          name: "Testimonial Collection",
          description: "Gather customer testimonials with photo and permission to share",
          category: "feedback",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "About You" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Job Title" }],
            [{ type: :input, width: "half", label: "Company / Organization" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "City / Country" }, { type: :select, width: "half", label: "Industry" }],
            [{ type: :input, width: "half", label: "LinkedIn / Website (optional)" }, { type: :select, width: "half", label: "How Long Have You Been a Customer?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Testimonial" }],
            [{ type: :select, width: "half", label: "Product / Service Used" }, { type: :select, width: "half", label: "Overall Rating (1-5 Stars)" }],
            [{ type: :textarea, width: "full", label: "Your Testimonial / Review" }],
            [{ type: :textarea, width: "full", label: "Specific Results or Outcomes You Experienced" }],
            [{ type: :select, width: "half", label: "Would you recommend us? (Definitely, Likely, Not Sure)" }, { type: :radio, width: "half", label: "May we contact you for a more detailed case study?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Photo & Consent" }],
            [{ type: :file, width: "full", label: "Upload Your Headshot / Profile Photo" }],
            [{ type: :checkbox, width: "full", label: "I grant permission to publish my testimonial with my name, title, and company" }],
            [{ type: :checkbox, width: "full", label: "I grant permission to use my photo alongside my testimonial on the website and marketing materials" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "file" => "full",
              "url" => "half",
            },
            sections: [
              { label: "About You", match_types: %w[text email tel select url] },
              { label: "Your Testimonial", match_types: %w[textarea radio] },
              { label: "Photo & Consent", match_types: %w[file checkbox] }
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
