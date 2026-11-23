# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Education
      module ParentPermission
        DEFINITION = {
          key: "parent_permission",
          name: "Parent Permission Slip",
          description: "School permission form with emergency contacts and medical info",
          category: "education",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Student Information" }],
            [{ type: :input, width: "half", label: "Student Name" }, { type: :select, width: "half", label: "Grade" }],
            [{ type: :input, width: "half", label: "Teacher / Class" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :divider }],
            [{ type: :section, label: "Parent / Guardian" }],
            [{ type: :input, width: "half", label: "Parent / Guardian Name" }, { type: :input, width: "half", label: "Relationship to Student" }],
            [{ type: :input, width: "half", label: "Phone (Primary)" }, { type: :input, width: "half", label: "Phone (Secondary)" }],
            [{ type: :input, width: "full", label: "Email Address" }],
            [{ type: :divider }],
            [{ type: :section, label: "Event / Activity Details" }],
            [{ type: :input, width: "half", label: "Event / Activity Name" }, { type: :date, width: "half", label: "Event Date" }],
            [{ type: :input, width: "half", label: "Destination / Location" }, { type: :input, width: "half", label: "Return Time" }],
            [{ type: :textarea, width: "full", label: "Medical Conditions, Allergies, or Special Instructions" }],
            [{ type: :textarea, width: "full", label: "Emergency Contact (Name, Relationship, Phone)" }],
            [{ type: :checkbox, width: "full", label: "I grant permission for my child to participate in this activity" }],
            [{ type: :checkbox, width: "full", label: "I authorize emergency medical treatment if needed" }],
            [{ type: :signature, width: "full", label: "Parent / Guardian Signature" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "full",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "textarea" => "full",
              "checkbox" => "full",
            },
            sections: [
              { label: "Student & Parent Info", match_types: %w[text email tel select date] },
              { label: "Event Details", match_types: %w[textarea] },
              { label: "Permission & Signature", match_types: %w[checkbox] }
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
