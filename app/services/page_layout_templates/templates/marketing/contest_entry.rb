# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Marketing
      module ContestEntry
        DEFINITION = {
          key: "contest_entry",
          name: "Contest / Giveaway",
          description: "Sweepstakes entry with social sharing and eligibility confirmation",
          category: "marketing",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Enter to Win!" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone (Optional)" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :input, width: "half", label: "City / State" }],
            [{ type: :select, width: "half", label: "Country" }, { type: :select, width: "half", label: "How did you hear about this contest? (Social Media, Email, Friend, Ad, Website, Other)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Bonus Entries" }],
            [{ type: :checkbox, width: "full", label: "Bonus Entry: Follow us on Instagram, Share on Facebook, Tag a Friend, Subscribe to Newsletter" }],
            [{ type: :input, width: "half", label: "Social Media Handle (for bonus entry verification)" }, { type: :input, width: "half", label: "Referral Code (if any)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Eligibility & Consent" }],
            [{ type: :checkbox, width: "full", label: "I am 18 years of age or older and a legal resident of the eligible region" }],
            [{ type: :checkbox, width: "full", label: "I agree to the contest rules and official terms and conditions" }],
            [{ type: :checkbox, width: "full", label: "I consent to receive marketing communications from this company" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "checkbox" => "full"
            },
            sections: [
              { label: "Your Information", match_types: %w[text email tel date select url] },
              { label: "Bonus Entries", match_types: %w[checkbox] },
              { label: "Eligibility & Consent", match_types: %w[] }
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
