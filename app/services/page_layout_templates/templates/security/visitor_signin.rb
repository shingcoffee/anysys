# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Security
      module VisitorSignin
        DEFINITION = {
          key: "visitor_signin",
          name: "Visitor Sign-in",
          description: "Building visitor registration with host, purpose, and badge issuance",
          category: "security",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Visitor Information" }],
            [{ type: :input, width: "half", label: "Visitor Full Name" }, { type: :input, width: "half", label: "Company / Organization" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :select, width: "half", label: "ID Type (Driver's License, Passport, National ID)" }, { type: :input, width: "half", label: "ID Number (last 4 digits)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Visit Details" }],
            [{ type: :input, width: "half", label: "Host Name" }, { type: :select, width: "half", label: "Host Department" }],
            [{ type: :select, width: "half", label: "Purpose of Visit (Meeting, Delivery, Interview, Tour, Maintenance, Other)" }, { type: :date, width: "half", label: "Visit Date" }],
            [{ type: :input, width: "half", label: "Expected Check-in Time" }, { type: :input, width: "half", label: "Expected Check-out Time" }],
            [{ type: :input, width: "half", label: "Floor / Area to Visit" }, { type: :input, width: "half", label: "Badge Number (issued by reception)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Security & Consent" }],
            [{ type: :file, width: "full", label: "Photo ID Upload" }],
            [{ type: :checkbox, width: "full", label: "Carrying electronic devices (laptop, camera, recording equipment)" }],
            [{ type: :radio, width: "full", label: "Has this visitor been pre-approved?" }],
            [{ type: :checkbox, width: "full", label: "I agree to abide by all building security policies and NDAs" }],
            [{ type: :signature, width: "full", label: "Visitor Signature" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "file" => "full",
              "checkbox" => "full",
              "radio" => "full",
              "time" => "half",
            },
            sections: [
              { label: "Visitor Info", match_types: %w[text email tel] },
              { label: "Visit Details", match_types: %w[select date radio time] },
              { label: "ID & Policies", match_types: %w[file checkbox] }
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
