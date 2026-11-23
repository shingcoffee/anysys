# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Wedding
      module VendorInquiry
        DEFINITION = {
          key: "wedding_vendor_inquiry",
          name: "Wedding Vendor Inquiry",
          description: "Couple-to-vendor inquiry with wedding date, style preferences, budget, and venue details",
          category: "wedding",
          theme_preset: "elegant",
          preview_rows: [
            [{ type: :section, label: "Couple & Contact" }],
            [{ type: :input, width: "half", label: "Partner 1 Name" }, { type: :input, width: "half", label: "Partner 2 Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Phone Number" }],
            [{ type: :date, width: "half", label: "Wedding Date" }, { type: :input, width: "half", label: "Venue / Location Name" }],
            [{ type: :input, width: "half", label: "City / State" }, { type: :select, width: "half", label: "How Did You Find Us?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Wedding Details" }],
            [{ type: :number, width: "half", label: "Estimated Guest Count" }, { type: :select, width: "half", label: "Ceremony Type (Church, Garden, Beach, Courthouse, Destination, Other)" }],
            [{ type: :select, width: "half", label: "Wedding Style (Classic, Rustic, Modern, Bohemian, Glamorous, Vintage, Other)" }, { type: :select, width: "half", label: "Overall Budget Range" }],
            [{ type: :select, width: "half", label: "Service Needed (Photography, Videography, Catering, Florals, DJ, Band, Planning, Decor, Other)" }, { type: :select, width: "half", label: "Budget for This Service" }],
            [{ type: :radio, width: "full", label: "Have you already booked a venue?" }],
            [{ type: :radio, width: "full", label: "Are there other vendors already confirmed?" }],
            [{ type: :divider }],
            [{ type: :section, label: "Vision & Inspiration" }],
            [{ type: :textarea, width: "full", label: "Tell Us About Your Vision and What Makes Your Wedding Unique" }],
            [{ type: :textarea, width: "full", label: "Any Specific Requirements or Must-Haves for This Service?" }],
            [{ type: :file, width: "full", label: "Upload Inspiration / Mood Board Photos (optional)" }],
            [{ type: :checkbox, width: "full", label: "I am interested in scheduling a consultation or call to discuss further" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "date" => "half",
              "number" => "half",
              "select" => "half",
              "textarea" => "full",
              "file" => "full",
              "radio" => "full",
              "checkbox" => "full"
            },
            sections: [
              { label: "Couple & Contact", match_types: %w[text email tel date] },
              { label: "Wedding Details", match_types: %w[number select radio] },
              { label: "Vision & Inspiration", match_types: %w[textarea file checkbox] }
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
