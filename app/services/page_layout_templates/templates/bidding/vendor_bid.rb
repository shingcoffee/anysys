# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Bidding
      module VendorBid
        DEFINITION = {
          key: "vendor_bid_response",
          name: "Vendor Bid Response",
          description: "Vendor bid response form for procurement with line-item pricing, delivery terms, and warranty details",
          category: "bidding",
          theme_preset: "minimalist",
          preview_rows: [
            [{ type: :section, label: "Vendor Information" }],
            [{ type: :input, width: "half", label: "Company / Vendor Legal Name" }, { type: :input, width: "half", label: "Vendor ID / Account Number" }],
            [{ type: :input, width: "half", label: "Primary Contact Person" }, { type: :input, width: "half", label: "Contact Title / Role" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :input, width: "full", label: "Business Address" }],
            [{ type: :input, width: "half", label: "Federal Tax ID / EIN" }, { type: :input, width: "half", label: "DUNS Number (if applicable)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Pricing & Delivery" }],
            [{ type: :input, width: "half", label: "RFP / Bid Reference Number" }, { type: :input, width: "half", label: "Procurement Agency / Buyer" }],
            [{ type: :date, width: "half", label: "Bid Submission Date" }, { type: :date, width: "half", label: "Bid Valid Until Date" }],
            [{ type: :input, width: "full", label: "Item / Service Description (Line 1)" }],
            [{ type: :number, width: "third", label: "Quantity" }, { type: :number, width: "third", label: "Unit Price ($)" }, { type: :number, width: "third", label: "Line Total ($)" }],
            [{ type: :input, width: "full", label: "Item / Service Description (Line 2)" }],
            [{ type: :number, width: "third", label: "Quantity" }, { type: :number, width: "third", label: "Unit Price ($)" }, { type: :number, width: "third", label: "Line Total ($)" }],
            [{ type: :number, width: "half", label: "Subtotal ($)" }, { type: :number, width: "half", label: "Applicable Taxes ($)" }],
            [{ type: :number, width: "half", label: "Shipping / Delivery Charges ($)" }, { type: :number, width: "half", label: "Total Bid Amount ($)" }],
            [{ type: :select, width: "half", label: "Currency" }, { type: :radio, width: "half", label: "Price Includes All Fees?" }],
            [{ type: :select, width: "half", label: "Payment Terms (Net 30, Net 60, COD, Prepayment)" }, { type: :number, width: "half", label: "Lead Time / Delivery Time (Days)" }],
            [{ type: :date, width: "half", label: "Estimated Delivery Date" }, { type: :select, width: "half", label: "Shipping / Delivery Method" }],
            [{ type: :radio, width: "full", label: "Is installation or setup included?" }],
            [{ type: :select, width: "half", label: "Warranty Period (Months / Years)" }, { type: :select, width: "half", label: "Warranty Type (Full, Limited, Parts Only)" }],
            [{ type: :checkbox, width: "full", label: "Certifications (ISO 9001, ISO 14001, MBE, WBE, Veteran-Owned, Small Business, Other)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Terms & Documents" }],
            [{ type: :textarea, width: "full", label: "Executive Summary, Relevant Experience & Past Performance" }],
            [{ type: :textarea, width: "full", label: "Terms, Conditions, Exclusions, and Assumptions" }],
            [{ type: :file, width: "full", label: "Upload Supporting Documentation (Specs, Certifications, Insurance, References)" }],
            [{ type: :checkbox, width: "full", label: "I certify this bid is binding and accurate for the stated validity period" }],
            [{ type: :signature, width: "full", label: "Authorized Signature" }],
            [{ type: :date, width: "half", label: "Signature Date" }, { type: :input, width: "half", label: "Signatory Name & Title" }]
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
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
            },
            sections: [
              { label: "Vendor Information", match_types: %w[text email tel] },
              { label: "Pricing & Delivery", match_types: %w[number select date radio checkbox] },
              { label: "Terms & Documents", match_types: %w[textarea file] }
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
