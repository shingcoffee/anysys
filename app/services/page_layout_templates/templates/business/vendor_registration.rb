# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Business
      module VendorRegistration
        DEFINITION = {
          key: "vendor_registration",
          name: "Vendor Registration",
          description: "Supplier onboarding with business details, tax info, and banking",
          category: "business",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Company Information" }],
            [{ type: :input, width: "full", label: "Legal Company Name" }],
            [{ type: :input, width: "half", label: "Doing Business As (DBA)" }, { type: :select, width: "half", label: "Business Entity Type (LLC, Corp, Partnership, Sole Prop)" }],
            [{ type: :input, width: "half", label: "Federal Tax ID / EIN" }, { type: :input, width: "half", label: "DUNS Number (if applicable)" }],
            [{ type: :input, width: "half", label: "Year Established" }, { type: :input, width: "half", label: "Number of Employees" }],
            [{ type: :input, width: "full", label: "Business Address" }],
            [{ type: :input, width: "half", label: "City" }, { type: :input, width: "half", label: "State / ZIP Code" }],
            [{ type: :input, width: "half", label: "Country" }, { type: :input, width: "half", label: "Business Website" }],
            [{ type: :input, width: "half", label: "Contact Person Name" }, { type: :input, width: "half", label: "Title / Position" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :divider }],
            [{ type: :section, label: "Tax & Financial" }],
            [{ type: :select, width: "half", label: "Industry / Sector" }, { type: :input, width: "half", label: "Primary Products / Services Offered" }],
            [{ type: :textarea, width: "full", label: "Detailed Description of Products / Services" }],
            [{ type: :checkbox, width: "full", label: "Certifications (MBE, WBE, Veteran-Owned, Small Business, ISO 9001, ISO 14001, Other)" }],
            [{ type: :input, width: "half", label: "Bank Name" }, { type: :select, width: "half", label: "Account Type (Checking, Savings)" }],
            [{ type: :input, width: "half", label: "Routing Number (ABA)" }, { type: :input, width: "half", label: "Account Number" }],
            [{ type: :select, width: "full", label: "Preferred Payment Method (ACH, Wire Transfer, Check, Credit Card)" }],
            [{ type: :select, width: "half", label: "Payment Terms Requested (Net 15, Net 30, Net 60)" }, { type: :input, width: "half", label: "Currency Preference" }],
            [{ type: :radio, width: "full", label: "Do you carry General Liability Insurance?" }],
            [{ type: :number, width: "half", label: "Coverage Amount ($)" }, { type: :date, width: "half", label: "Policy Expiration Date" }],
            [{ type: :divider }],
            [{ type: :section, label: "Documents & Certification" }],
            [{ type: :input, width: "half", label: "Reference 1 — Company & Contact" }, { type: :input, width: "half", label: "Reference 2 — Company & Contact" }],
            [{ type: :file, width: "full", label: "Upload W-9, Business License, Insurance Certificate, Certifications (Required)" }],
            [{ type: :file, width: "full", label: "Company Brochure / Capabilities Statement (optional)" }],
            [{ type: :checkbox, width: "full", label: "I certify that all information provided is accurate, complete, and I agree to comply with all terms and conditions" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "date" => "half",
              "select" => "half",
              "checkbox" => "full",
              "radio" => "full",
              "file" => "full",
              "textarea" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Company Information", match_types: %w[text email tel url] },
              { label: "Tax & Financial", match_types: %w[number select date radio checkbox textarea] },
              { label: "Documents & Certification", match_types: %w[file] }
            ],
            inject_elements: [{ after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }]
          }
        }.freeze
      end
    end
  end
end
