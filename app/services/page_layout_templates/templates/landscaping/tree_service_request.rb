# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Landscaping
      module TreeServiceRequest
        DEFINITION = {
          key: "tree_service_request",
          name: "Tree Service Request",
          description: "Tree removal, trimming, or stump grinding request with location, species, and hazard assessment",
          category: "landscaping",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Contact Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "full", label: "Property Address" }],
            [{ type: :select, width: "half", label: "Property Type (Residential, Commercial, Municipal)" }, { type: :radio, width: "half", label: "Own or Rent?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Tree & Service Details" }],
            [{ type: :select, width: "half", label: "Service Type (Removal, Trimming, Pruning, Stump Grinding, Cabling, Emergency, Other)" }, { type: :select, width: "half", label: "Urgency (Emergency, This Week, Within a Month, Flexible)" }],
            [{ type: :number, width: "half", label: "Number of Trees" }, { type: :select, width: "half", label: "Estimated Height (< 20 ft, 20-40 ft, 40-60 ft, 60+ ft)" }],
            [{ type: :select, width: "half", label: "Tree Species (if known)" }, { type: :select, width: "half", label: "Trunk Diameter (< 6 in, 6-12 in, 12-24 in, 24+ in)" }],
            [{ type: :select, width: "half", label: "Proximity to Structures (None, < 10 ft, 10-20 ft, > 20 ft)" }, { type: :select, width: "half", label: "Access to Site (Easy, Restricted, Requires Equipment)" }],
            [{ type: :radio, width: "full", label: "Is the tree dead, diseased, or structurally compromised?" }],
            [{ type: :radio, width: "full", label: "Are power lines within 10 feet of the tree?" }],
            [{ type: :radio, width: "full", label: "Is the tree causing active damage to property?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Description & Scheduling" }],
            [{ type: :textarea, width: "full", label: "Describe the Situation or Concern" }],
            [{ type: :date, width: "half", label: "Preferred Service Date" }, { type: :select, width: "half", label: "Preferred Time Window" }],
            [{ type: :file, width: "full", label: "Photos of Tree(s)" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "select" => "half",
              "number" => "half",
              "date" => "half",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel] },
              { label: "Tree & Service Details", match_types: %w[select number radio] },
              { label: "Description & Photos", match_types: %w[date textarea file] }
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
