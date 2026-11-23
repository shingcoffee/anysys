# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Coworking
      module CommunityMembership
        DEFINITION = {
          key: "community_membership",
          name: "Community Membership",
          description: "Coworking space membership application with plan selection and access preferences",
          category: "coworking",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Company / Freelancer Name" }],
            [{ type: :input, width: "half", label: "Job Title / Role" }, { type: :select, width: "half", label: "Industry" }],
            [{ type: :input, width: "half", label: "Website" }, { type: :input, width: "half", label: "LinkedIn Profile URL" }],
            [{ type: :divider }],
            [{ type: :section, label: "Membership Details" }],
            [{ type: :select, width: "half", label: "Membership Plan (Hot Desk, Dedicated Desk, Private Office, Virtual)" }, { type: :date, width: "half", label: "Desired Start Date" }],
            [{ type: :select, width: "half", label: "Preferred Location" }, { type: :select, width: "half", label: "Working Hours (Business Hours, Extended, 24/7)" }],
            [{ type: :select, width: "half", label: "Billing Cycle (Monthly, Quarterly, Annual)" }, { type: :select, width: "half", label: "Preferred Payment Method" }],
            [{ type: :number, width: "half", label: "Number of Team Members (if team plan)" }, { type: :select, width: "half", label: "How Long Do You Need the Space?" }],
            [{ type: :checkbox, width: "full", label: "Add-On Services (Meeting Rooms, Mail Handling, Printing, Locker, Phone Booth, Events Access, Parking)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Preferences & Agreement" }],
            [{ type: :select, width: "half", label: "How Did You Hear About Us?" }, { type: :radio, width: "half", label: "Have you worked in a coworking space before?" }],
            [{ type: :textarea, width: "full", label: "What do you hope to get from this community?" }],
            [{ type: :checkbox, width: "full", label: "I agree to the house rules, membership policies, and code of conduct" }],
            [{ type: :checkbox, width: "full", label: "I consent to my information being used for membership management and community communications" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "number" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Personal Info", match_types: %w[text email tel url] },
              { label: "Membership Details", match_types: %w[select date number] },
              { label: "Preferences & Agreement", match_types: %w[checkbox radio textarea] }
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
