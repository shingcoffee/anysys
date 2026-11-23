# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Creative
      module PortfolioSubmission
        DEFINITION = {
          key: "portfolio_submission",
          name: "Portfolio Submission",
          description: "Creative portfolio upload with project descriptions and links",
          category: "creative",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "About You" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :select, width: "half", label: "Creative Specialty (Graphic Design, Illustration, Photography, Video, UX/UI, Animation, Other)" }],
            [{ type: :input, width: "half", label: "Website / Portfolio URL" }, { type: :input, width: "half", label: "LinkedIn / Behance / Dribbble Profile" }],
            [{ type: :select, width: "half", label: "Years of Experience (0-1, 2-4, 5-9, 10+)" }, { type: :select, width: "half", label: "Availability (Full-Time, Part-Time, Freelance, Contract)" }],
            [{ type: :input, width: "half", label: "Current Location / City" }, { type: :radio, width: "half", label: "Open to remote work?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Portfolio Pieces" }],
            [{ type: :input, width: "full", label: "Project Title" }],
            [{ type: :select, width: "half", label: "Project Category (Branding, Web, Print, Photography, Video, Illustration, Other)" }, { type: :input, width: "half", label: "Client / Employer (or Personal Project)" }],
            [{ type: :date, width: "half", label: "Project Date / Year" }, { type: :input, width: "half", label: "Live Project URL (if applicable)" }],
            [{ type: :textarea, width: "full", label: "Project Description & Your Role" }],
            [{ type: :file, width: "full", label: "Upload Work Samples (Images, PDF, Video — max 10 files)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Statement & Agreement" }],
            [{ type: :textarea, width: "full", label: "About You / Creative Philosophy" }],
            [{ type: :textarea, width: "full", label: "What are you looking for? (Opportunities, Collaboration, etc.)" }],
            [{ type: :checkbox, width: "full", label: "I certify all submitted work is my original creation or I have rights to share it" }]
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
              "textarea" => "full",
              "checkbox" => "full",
              "file" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel select url] },
              { label: "Portfolio", match_types: %w[textarea file date radio] },
              { label: "Statement & Agreement", match_types: %w[checkbox] }
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
