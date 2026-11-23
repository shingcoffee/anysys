# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Recruitment
      module CandidateScreening
        DEFINITION = {
          key: "candidate_screening",
          name: "Candidate Screening",
          description: "Pre-interview screening questionnaire with experience, skills, and availability",
          category: "recruitment",
          theme_preset: "modern",
          preview_rows: [
            [{ type: :section, label: "Personal Information" }],
            [{ type: :input, width: "half", label: "Full Name" }, { type: :input, width: "half", label: "Email" }],
            [{ type: :input, width: "half", label: "Phone" }, { type: :input, width: "half", label: "LinkedIn Profile URL" }],
            [{ type: :input, width: "half", label: "City" }, { type: :select, width: "half", label: "Country" }],
            [{ type: :divider }],
            [{ type: :section, label: "Position & Experience" }],
            [{ type: :input, width: "half", label: "Position Applied For" }, { type: :input, width: "half", label: "Job Requisition ID" }],
            [{ type: :select, width: "half", label: "Years of Relevant Experience" }, { type: :select, width: "half", label: "Highest Education Level" }],
            [{ type: :number, width: "half", label: "Expected Salary (Annual)" }, { type: :select, width: "half", label: "Currency" }],
            [{ type: :date, width: "half", label: "Available Start Date" }, { type: :select, width: "half", label: "Employment Type (Full-time, Part-time, Contract, Internship)" }],
            [{ type: :radio, width: "full", label: "Work Authorization Status (Authorized, Require Sponsorship, Other)" }],
            [{ type: :radio, width: "full", label: "Willing to Relocate?" }],
            [{ type: :radio, width: "full", label: "Open to Remote / Hybrid Work?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Skills & Background" }],
            [{ type: :textarea, width: "full", label: "Relevant Skills & Certifications" }],
            [{ type: :textarea, width: "full", label: "Brief Summary of Most Recent Role" }],
            [{ type: :textarea, width: "full", label: "Why are you interested in this role?" }],
            [{ type: :select, width: "half", label: "How did you hear about this position?" }, { type: :input, width: "half", label: "Referral Name (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Documents" }],
            [{ type: :file, width: "full", label: "Resume / CV" }],
            [{ type: :file, width: "full", label: "Cover Letter (optional)" }],
            [{ type: :checkbox, width: "full", label: "I confirm the information provided is accurate and complete" }]
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
              "file" => "full",
              "checkbox" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Contact Info", match_types: %w[text email tel url] },
              { label: "Position & Experience", match_types: %w[select number date radio] },
              { label: "Skills & Documents", match_types: %w[textarea file checkbox] }
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
