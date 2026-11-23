# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Childcare
      module AfterschoolProgram
        DEFINITION = {
          key: "afterschool_program",
          name: "After-School Program",
          description: "After-school activity enrollment with child info, pickup authorization, and medical details",
          category: "childcare",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Child Information" }],
            [{ type: :input, width: "half", label: "Child's First Name" }, { type: :input, width: "half", label: "Child's Last Name" }],
            [{ type: :date, width: "half", label: "Date of Birth" }, { type: :select, width: "half", label: "Current Grade (K, 1st–8th)" }],
            [{ type: :input, width: "half", label: "School Name" }, { type: :input, width: "half", label: "Teacher Name / Classroom" }],
            [{ type: :divider }],
            [{ type: :section, label: "Parent / Guardian Information" }],
            [{ type: :input, width: "half", label: "Parent / Guardian Full Name" }, { type: :select, width: "half", label: "Relationship to Child" }],
            [{ type: :input, width: "half", label: "Primary Phone" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "full", label: "Home Address" }],
            [{ type: :input, width: "half", label: "Work Phone" }, { type: :input, width: "half", label: "Employer Name" }],
            [{ type: :input, width: "half", label: "Emergency Contact Name" }, { type: :input, width: "half", label: "Emergency Contact Phone" }],
            [{ type: :select, width: "half", label: "Emergency Contact Relationship" }, { type: :input, width: "half", label: "Emergency Contact Email" }],
            [{ type: :divider }],
            [{ type: :section, label: "Program & Medical" }],
            [{ type: :checkbox, width: "full", label: "Activities (Homework Help, Arts & Crafts, Sports/PE, Music, STEM/Robotics, Outdoor Play, Reading Club, Computer Lab)" }],
            [{ type: :checkbox, width: "full", label: "Days Needed (Monday, Tuesday, Wednesday, Thursday, Friday)" }],
            [{ type: :select, width: "half", label: "Pickup Time" }, { type: :date, width: "half", label: "Enrollment Start Date" }],
            [{ type: :select, width: "half", label: "Session (Full Year, Semester, Summer)" }, { type: :number, width: "half", label: "Number of Children Enrolling" }],
            [{ type: :textarea, width: "full", label: "Authorized Pickup Persons (Name, Relationship, Phone)" }],
            [{ type: :radio, width: "full", label: "May child walk home alone if permitted?" }],
            [{ type: :textarea, width: "full", label: "Known Allergies (Food, Medication, Environmental)" }],
            [{ type: :textarea, width: "full", label: "Medical Conditions, Special Needs, or Behavioral Notes" }],
            [{ type: :radio, width: "full", label: "Does the child require daily medication?" }],
            [{ type: :textarea, width: "full", label: "Medication Name & Dosage Instructions (if applicable)" }],
            [{ type: :input, width: "half", label: "Pediatrician Name" }, { type: :input, width: "half", label: "Pediatrician Phone" }],
            [{ type: :file, width: "full", label: "Upload Immunization Records (if required)" }],
            [{ type: :checkbox, width: "full", label: "I authorize emergency medical treatment if parent cannot be reached and agree to program policies" }]
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
              "file" => "full"
            },
            sections: [
              { label: "Child & School", match_types: %w[text date select] },
              { label: "Parent / Guardian", match_types: %w[email tel] },
              { label: "Program & Medical", match_types: %w[checkbox radio textarea file number] }
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
