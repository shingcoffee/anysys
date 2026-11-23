# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Fitness
      module PersonalTrainingIntake
        DEFINITION = {
          key: "personal_training_intake",
          name: "Personal Training Intake",
          description: "New client assessment with fitness goals, health history, and availability",
          category: "fitness",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Personal Info" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :date, width: "half", label: "Date of Birth" }],
            [{ type: :select, width: "half", label: "Gender" }, { type: :number, width: "half", label: "Height (cm or ft/in)" }],
            [{ type: :number, width: "half", label: "Current Weight (lbs/kg)" }, { type: :number, width: "half", label: "Goal Weight (lbs/kg)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Fitness Goals & History" }],
            [{ type: :select, width: "half", label: "Current Activity Level (Sedentary, Light, Moderate, Active, Very Active)" }, { type: :select, width: "half", label: "Training Experience (Beginner, Intermediate, Advanced)" }],
            [{ type: :checkbox, width: "full", label: "Fitness Goals (Weight Loss, Muscle Gain, Endurance, Flexibility, Sports Performance, Rehabilitation, General Wellness)" }],
            [{ type: :textarea, width: "full", label: "Exercise History (Types of Workouts, Frequency)" }],
            [{ type: :checkbox, width: "full", label: "Available Days (Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday)" }],
            [{ type: :select, width: "half", label: "Preferred Training Time (Morning, Afternoon, Evening)" }, { type: :select, width: "half", label: "Training Location Preference (In-Person, Online, Home, Gym)" }],
            [{ type: :select, width: "half", label: "Sessions per Week" }, { type: :select, width: "half", label: "Session Duration Preference (30 min, 45 min, 60 min)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Health Screening" }],
            [{ type: :radio, width: "full", label: "Do you have any injuries, medical conditions, or physical limitations?" }],
            [{ type: :textarea, width: "full", label: "Medical Details, Injuries, or Limitations (if yes)" }],
            [{ type: :radio, width: "full", label: "Are you currently under a doctor's care?" }],
            [{ type: :textarea, width: "full", label: "Current Medications, Supplements, or Dietary Restrictions" }],
            [{ type: :checkbox, width: "full", label: "I certify the above information is accurate and agree to the personal training liability waiver" }]
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
              "textarea" => "full"
            },
            sections: [
              { label: "Personal Info", match_types: %w[text email tel date select number] },
              { label: "Fitness Goals & History", match_types: %w[checkbox textarea range] },
              { label: "Health Screening", match_types: %w[radio] }
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
