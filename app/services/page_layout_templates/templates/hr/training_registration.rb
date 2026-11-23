# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Hr
      module TrainingRegistration
        DEFINITION = {
          key: "training_registration",
          name: "Training Registration",
          description: "Employee training enrollment with course selection and scheduling",
          category: "hr",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Participant Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Employee ID" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :select, width: "half", label: "Department" }, { type: :select, width: "half", label: "Job Level / Grade" }],
            [{ type: :input, width: "half", label: "Manager Name" }, { type: :input, width: "half", label: "Manager Email" }],
            [{ type: :divider }],
            [{ type: :section, label: "Training Details" }],
            [{ type: :select, width: "half", label: "Course / Program Name" }, { type: :select, width: "half", label: "Training Category (Technical, Leadership, Compliance, Safety, Soft Skills, Other)" }],
            [{ type: :date, width: "half", label: "Preferred Start Date" }, { type: :select, width: "half", label: "Session Time Preference" }],
            [{ type: :radio, width: "full", label: "Delivery Format (In-Person, Online, Hybrid, Self-Paced)" }],
            [{ type: :select, width: "half", label: "Training Duration (Half Day, Full Day, Multi-Day, Weeks)" }, { type: :select, width: "half", label: "Funding Source (Company, Self-Funded, Grant, Tuition Assistance)" }],
            [{ type: :number, width: "half", label: "Estimated Cost ($)" }, { type: :select, width: "half", label: "Priority Level (Required, Recommended, Optional)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Justification & Approval" }],
            [{ type: :textarea, width: "full", label: "Learning Objectives & How This Training Supports Your Role" }],
            [{ type: :textarea, width: "full", label: "How Will You Apply This Training on the Job?" }],
            [{ type: :checkbox, width: "full", label: "I have obtained manager approval for this training request" }],
            [{ type: :checkbox, width: "full", label: "I agree to complete required pre-work and attend all sessions" }]
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
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Participant Info", match_types: %w[text email tel select] },
              { label: "Training Details", match_types: %w[date number radio] },
              { label: "Justification & Approval", match_types: %w[textarea checkbox] }
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
