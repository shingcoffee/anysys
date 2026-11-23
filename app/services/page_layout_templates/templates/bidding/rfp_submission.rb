# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Bidding
      module RfpSubmission
        DEFINITION = {
          key: "rfp_submission",
          name: "RFP / Bid Submission",
          description: "Request for proposal or bid submission with company qualifications, pricing, timeline, and supporting documents",
          category: "bidding",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Company Information" }],
            [{ type: :input, width: "half", label: "Company Name" }, { type: :input, width: "half", label: "Contact Person" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Business Address" }],
            [{ type: :input, width: "half", label: "License / Registration Number" }, { type: :input, width: "half", label: "DUNS / SAM Number" }],
            [{ type: :select, width: "half", label: "Business Entity Type (LLC, Corp, Sole Prop, Partnership, Nonprofit)" }, { type: :select, width: "half", label: "Business Size (Small, Medium, Large, Enterprise)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Bid Details" }],
            [{ type: :input, width: "half", label: "RFP / Project Reference Number" }, { type: :select, width: "half", label: "Bid Category (Construction, IT, Consulting, Supplies, Services, Other)" }],
            [{ type: :number, width: "half", label: "Total Bid Amount ($)" }, { type: :select, width: "half", label: "Currency (USD, EUR, GBP, Other)" }],
            [{ type: :date, width: "half", label: "Proposed Start Date" }, { type: :date, width: "half", label: "Estimated Completion Date" }],
            [{ type: :number, width: "half", label: "Number of Employees / Resources" }, { type: :select, width: "half", label: "Performance Bond Available? (Yes, No, Upon Request)" }],
            [{ type: :radio, width: "full", label: "Are you a certified minority, woman, or veteran-owned business?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Proposal & Documents" }],
            [{ type: :textarea, width: "full", label: "Executive Summary and Proposed Approach" }],
            [{ type: :textarea, width: "full", label: "Relevant Experience, Qualifications, and References" }],
            [{ type: :file, width: "full", label: "Upload Proposal Documents, Certifications, and Supporting Files" }],
            [{ type: :checkbox, width: "full", label: "I certify that all information is accurate, complete, and submitted in good faith" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "date" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "textarea" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Company Information", match_types: %w[text email tel] },
              { label: "Bid Details", match_types: %w[number select date radio] },
              { label: "Proposal & Documents", match_types: %w[textarea file checkbox] }
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
