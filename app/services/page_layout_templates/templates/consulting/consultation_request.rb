# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Consulting
      module ConsultationRequest
        DEFINITION = {
          key: "consultation_request",
          name: "Consultation Request",
          description: "Professional consultation booking with topic, availability, and goals",
          category: "consulting",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Company / Organization" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Job Title" }, { type: :input, width: "half", label: "Industry" }],
            [{ type: :input, width: "half", label: "Company Website" }, { type: :select, width: "half", label: "Company Size (1-10, 11-50, 51-200, 200+)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Consultation Details" }],
            [{ type: :select, width: "half", label: "Service Area (Strategy, Operations, Finance, HR, IT, Marketing, Legal, Other)" }, { type: :select, width: "half", label: "Consultation Duration (30 min, 1 hour, 2 hours, Half Day)" }],
            [{ type: :date, width: "half", label: "Preferred Date" }, { type: :select, width: "half", label: "Preferred Time Window" }],
            [{ type: :date, width: "half", label: "Alternate Date" }, { type: :select, width: "half", label: "Alternate Time Window" }],
            [{ type: :radio, width: "full", label: "Meeting Format (In-Person, Video Call, Phone)" }],
            [{ type: :select, width: "half", label: "Budget Range" }, { type: :select, width: "half", label: "Urgency Level (This Week, This Month, Flexible)" }],
            [{ type: :radio, width: "full", label: "Have you worked with a consultant before?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Goals" }],
            [{ type: :textarea, width: "full", label: "Describe Your Challenge or Current Situation" }],
            [{ type: :textarea, width: "full", label: "Desired Outcomes & Goals" }],
            [{ type: :checkbox, width: "full", label: "Areas of Focus (Cost Reduction, Growth Strategy, Team Efficiency, Technology, Compliance, Risk Management, Other)" }],
            [{ type: :file, width: "full", label: "Upload Supporting Documents (optional)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "date" => "half",
              "radio" => "full",
              "textarea" => "full",
              "checkbox" => "full",
              "file" => "full",
              "url" => "half",
              "time" => "half",
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel url] },
              { label: "Consultation Details", match_types: %w[select date radio time] },
              { label: "Your Goals", match_types: %w[textarea checkbox file] }
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
