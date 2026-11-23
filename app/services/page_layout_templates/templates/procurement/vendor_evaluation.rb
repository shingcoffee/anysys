# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Procurement
      module VendorEvaluation
        DEFINITION = {
          key: "vendor_evaluation",
          name: "Vendor Evaluation",
          description: "Supplier performance evaluation with quality, delivery, pricing, and service ratings",
          category: "procurement",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Vendor & Evaluator Information" }],
            [{ type: :input, width: "half", label: "Vendor Name" }, { type: :input, width: "half", label: "Vendor ID / Account Number" }],
            [{ type: :input, width: "half", label: "Evaluator Name" }, { type: :input, width: "half", label: "Evaluator Department" }],
            [{ type: :date, width: "half", label: "Evaluation Period Start" }, { type: :date, width: "half", label: "Evaluation Period End" }],
            [{ type: :select, width: "half", label: "Vendor Category (Goods, Services, Software, Logistics, Consulting)" }, { type: :select, width: "half", label: "Contract Type (Annual, Project-Based, Spot Buy)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Performance Ratings" }],
            [{ type: :select, width: "half", label: "Product / Service Quality (1-5)" }, { type: :select, width: "half", label: "On-Time Delivery (1-5)" }],
            [{ type: :select, width: "half", label: "Pricing Competitiveness (1-5)" }, { type: :select, width: "half", label: "Communication & Responsiveness (1-5)" }],
            [{ type: :select, width: "half", label: "Issue Resolution (1-5)" }, { type: :select, width: "half", label: "Compliance & Documentation (1-5)" }],
            [{ type: :select, width: "half", label: "Innovation & Value-Add (1-5)" }, { type: :select, width: "half", label: "Overall Performance (1-5)" }],
            [{ type: :radio, width: "full", label: "Were there any supply disruptions or contract breaches during this period?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Comments & Recommendation" }],
            [{ type: :textarea, width: "full", label: "Strengths and Notable Achievements" }],
            [{ type: :textarea, width: "full", label: "Areas for Improvement" }],
            [{ type: :radio, width: "full", label: "Recommend for future contracts?" }],
            [{ type: :select, width: "half", label: "Recommended Action (Continue, Review, Probation, Terminate)" }, { type: :date, width: "half", label: "Next Evaluation Date" }],
            [{ type: :checkbox, width: "full", label: "This evaluation is accurate and has been reviewed by the evaluator" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "date" => "half",
              "select" => "half",
              "textarea" => "full",
              "radio" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Vendor Info", match_types: %w[text email date select] },
              { label: "Performance Ratings", match_types: %w[radio] },
              { label: "Comments & Recommendation", match_types: %w[textarea checkbox] }
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
