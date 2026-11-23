# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Payment
      module DonationForm
        DEFINITION = {
          key: "donation_form",
          name: "Donation Form",
          description: "Nonprofit donation with suggested amounts, recurring option, and donor info",
          category: "payment",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Donation Amount" }],
            [{ type: :radio, width: "full", label: "Suggested Amount ($25, $50, $100, $250, $500, Custom)" }],
            [{ type: :select, width: "half", label: "Donation Frequency (One-time, Monthly, Quarterly, Annual)" }, { type: :select, width: "half", label: "Fund / Campaign (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Donor Information" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone (Optional)" }],
            [{ type: :input, width: "full", label: "Home Address (for tax receipt)" }],
            [{ type: :select, width: "half", label: "Donor Type (Individual, Corporate, Foundation)" }, { type: :input, width: "half", label: "Company (for corporate gifts)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Options & Message" }],
            [{ type: :radio, width: "full", label: "Is this an anonymous donation?" }],
            [{ type: :radio, width: "full", label: "Is this donation in honor or memory of someone?" }],
            [{ type: :input, width: "full", label: "Honoree Name (if applicable)" }],
            [{ type: :textarea, width: "full", label: "Dedication Message / Comments" }],
            [{ type: :checkbox, width: "full", label: "I would like to receive updates about how my donation is being used" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Donation", match_types: %w[radio select range] },
              { label: "Donor Information", match_types: %w[text email tel url] },
              { label: "Options & Message", match_types: %w[textarea checkbox] }
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
