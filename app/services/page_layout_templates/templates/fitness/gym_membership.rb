# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Fitness
      module GymMembership
        DEFINITION = {
          key: "gym_membership",
          name: "Gym Membership",
          description: "Fitness club membership application with health screening and plan selection",
          category: "fitness",
          theme_preset: "bold",
          preview_rows: [
            [{ type: :section, label: "Personal Details" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :select, width: "half", label: "Gender" }, { type: :select, width: "half", label: "How Did You Hear About Us?" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Membership Plan" }],
            [{ type: :select, width: "half", label: "Membership Type (Basic, Standard, Premium, Family)" }, { type: :select, width: "half", label: "Billing Cycle (Monthly, Quarterly, Annual)" }],
            [{ type: :date, width: "half", label: "Desired Start Date" }, { type: :select, width: "half", label: "Home Location / Branch" }],
            [{ type: :number, width: "half", label: "Number of Members (for family plan)" }, { type: :select, width: "half", label: "Payment Method" }],
            [{ type: :checkbox, width: "full", label: "Add-On Services (Personal Training, Group Classes, Locker, Towel Service, Guest Passes, Sauna, Tanning)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Health & Terms" }],
            [{ type: :radio, width: "full", label: "Do you have any medical conditions, injuries, or physical limitations?" }],
            [{ type: :textarea, width: "full", label: "Medical Details (if yes)" }],
            [{ type: :radio, width: "full", label: "Are you currently under a doctor's care?" }],
            [{ type: :checkbox, width: "full", label: "I accept the membership terms, facility rules, and liability waiver" }],
            [{ type: :signature, width: "full", label: "Member Signature" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "select" => "half",
              "number" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
            },
            sections: [
              { label: "Personal Details", match_types: %w[text email tel date select] },
              { label: "Membership Plan", match_types: %w[number checkbox] },
              { label: "Health & Terms", match_types: %w[radio textarea] }
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
