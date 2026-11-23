# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Nonprofit
      module MembershipApplication
        DEFINITION = {
          key: "membership_application",
          name: "Membership Application",
          description: "Organization membership with tier selection and referral info",
          category: "nonprofit",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Applicant Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Address" }, { type: :input, width: "half", label: "City, State, ZIP" }],
            [{ type: :input, width: "half", label: "Company / Organization" }, { type: :input, width: "half", label: "Job Title" }],
            [{ type: :divider }],
            [{ type: :section, label: "Membership" }],
            [{ type: :radio, width: "full", label: "Membership Type (Individual, Family, Student, Corporate, Life, Honorary)" }],
            [{ type: :select, width: "half", label: "Membership Level / Tier" }, { type: :select, width: "half", label: "Payment Frequency (Annual, Monthly)" }],
            [{ type: :input, width: "half", label: "Referred By" }, { type: :select, width: "half", label: "How did you hear about us?" }],
            [{ type: :checkbox, width: "full", label: "Areas of Interest: Advocacy, Education, Community Programs, Events, Fundraising, Research, Volunteering" }],
            [{ type: :textarea, width: "full", label: "Why do you want to join?" }],
            [{ type: :checkbox, width: "full", label: "I agree to the membership terms and code of conduct" }]
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
              "url" => "half",
            },
            sections: [
              { label: "Personal Details", match_types: %w[text email tel date select url] },
              { label: "Membership Options", match_types: %w[radio checkbox textarea] },
              { label: "Agreement", match_types: %w[] }
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
