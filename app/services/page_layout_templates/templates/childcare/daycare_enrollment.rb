# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Childcare
      module DaycareEnrollment
        DEFINITION = {
          key: "daycare_enrollment",
          name: "Daycare Enrollment",
          description: "Child enrollment form with parent info, medical details, and emergency contacts",
          category: "childcare",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Child Information" }],
            [{ type: :input, width: "half", label: "Child's First Name" }, { type: :input, width: "half", label: "Child's Last Name" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :select, width: "half", label: "Gender (Male, Female, Non-Binary, Prefer Not to Say)" }],
            [{ type: :select, width: "half", label: "Program (Infant, Toddler, Pre-K, After School)" }, { type: :select, width: "half", label: "Start Date Requested" }],
            [{ type: :select, width: "half", label: "Schedule (Full-Time, Part-Time, Drop-In)" }, { type: :select, width: "half", label: "Days Needed (Mon-Fri, Mon/Wed/Fri, Tue/Thu)" }],
            [{ type: :input, width: "half", label: "Language Spoken at Home" }, { type: :input, width: "half", label: "Child's Nickname (if any)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Parent / Guardian" }],
            [{ type: :input, width: "half", label: "Parent / Guardian Full Name" }, { type: :select, width: "half", label: "Relationship to Child" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Work Phone" }, { type: :input, width: "half", label: "Employer / Workplace" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :input, width: "half", label: "Second Parent / Guardian Name" }, { type: :input, width: "half", label: "Second Parent Phone" }],
            [{ type: :divider }],
            [{ type: :section, label: "Medical & Emergency" }],
            [{ type: :input, width: "half", label: "Pediatrician Name" }, { type: :input, width: "half", label: "Doctor Phone Number" }],
            [{ type: :input, width: "half", label: "Preferred Hospital" }, { type: :input, width: "half", label: "Health Insurance Provider" }],
            [{ type: :textarea, width: "full", label: "Allergies (food, environmental, medication)" }],
            [{ type: :textarea, width: "full", label: "Medical Conditions, Diagnoses, or Special Needs" }],
            [{ type: :radio, width: "full", label: "Does your child require any daily medications?" }],
            [{ type: :textarea, width: "full", label: "Medication Instructions (if applicable)" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :select, width: "half", label: "Emergency Contact Relationship" }, { type: :radio, width: "half", label: "Is emergency contact authorized for pickup?" }],
            [{ type: :textarea, width: "full", label: "Other Authorized Pickup Persons (name and relationship)" }],
            [{ type: :file, width: "full", label: "Upload Immunization Records (required)" }],
            [{ type: :file, width: "full", label: "Upload Custody / Court Documents (if applicable)" }],
            [{ type: :checkbox, width: "full", label: "I authorize the facility to obtain emergency medical care and agree to all enrollment terms and policies" }]
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
              "textarea" => "full",
              "checkbox" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Child Information", match_types: %w[text date select] },
              { label: "Parent / Guardian", match_types: %w[email tel] },
              { label: "Medical & Emergency", match_types: %w[textarea checkbox radio file] }
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
