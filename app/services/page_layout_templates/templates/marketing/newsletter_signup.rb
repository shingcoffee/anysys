# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Marketing
      module NewsletterSignup
        DEFINITION = {
          key: "newsletter_signup",
          name: "Newsletter Signup",
          description: "Email capture with interest preferences and frequency selection",
          category: "marketing",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Your Details" }],
            [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
            [{ type: :input, width: "half", label: "Email Address" }, { type: :input, width: "half", label: "Company (Optional)" }],
            [{ type: :select, width: "half", label: "How did you hear about us? (Social Media, Friend, Search, Ad, Podcast, Other)" }, { type: :input, width: "half", label: "Referred By (Optional)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Your Interests" }],
            [{ type: :checkbox, width: "full", label: "Topics: Product Updates, Industry News, Tips & Tutorials, Case Studies, Events & Webinars, Promotions & Offers" }],
            [{ type: :select, width: "half", label: "Email Frequency (Daily, Weekly, Bi-Weekly, Monthly)" }, { type: :select, width: "half", label: "Preferred Format (HTML, Plain Text)" }],
            [{ type: :divider }],
            [{ type: :section, label: "Consent" }],
            [{ type: :checkbox, width: "full", label: "I agree to receive email communications and understand I can unsubscribe at any time" }],
            [{ type: :checkbox, width: "full", label: "I agree to the privacy policy" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "checkbox" => "full"
            },
            sections: [
              { label: "Your Details", match_types: %w[text email select] },
              { label: "Preferences", match_types: %w[checkbox] },
              { label: "Consent", match_types: %w[] }
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
