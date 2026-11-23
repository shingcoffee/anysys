# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Creator
      module BrandCollaboration
        DEFINITION = {
          key: "brand_collaboration",
          name: "Brand Collaboration",
          description: "Influencer brand partnership inquiry with audience stats, content style, and campaign preferences",
          category: "creator",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Creator Profile" }],
            [{ type: :input, width: "half", label: "Full Name / Creator Handle" }, { type: :input, width: "half", label: "Email Address" }],
            [{ type: :input, width: "half", label: "Phone Number" }, { type: :input, width: "half", label: "Website / Portfolio URL" }],
            [{ type: :select, width: "half", label: "Content Niche / Category" }, { type: :select, width: "half", label: "Country / Region" }],
            [{ type: :divider }],
            [{ type: :section, label: "Audience & Platform Stats" }],
            [{ type: :checkbox, width: "full", label: "Primary Platforms (Instagram, TikTok, YouTube, Twitter/X, LinkedIn, Pinterest, Blog, Podcast)" }],
            [{ type: :number, width: "half", label: "Total Followers / Subscribers" }, { type: :number, width: "half", label: "Average Monthly Views / Reach" }],
            [{ type: :number, width: "half", label: "Average Engagement Rate (%)" }, { type: :select, width: "half", label: "Primary Audience Age Group" }],
            [{ type: :select, width: "half", label: "Audience Gender Split" }, { type: :select, width: "half", label: "Top Audience Country" }],
            [{ type: :divider }],
            [{ type: :section, label: "Collaboration Details" }],
            [{ type: :checkbox, width: "full", label: "Content Types Available (Sponsored Post, Reel/Short, Story, YouTube Video, Blog, Newsletter, Podcast Mention, Giveaway)" }],
            [{ type: :select, width: "half", label: "Preferred Campaign Duration" }, { type: :select, width: "half", label: "Rate Range (per deliverable)" }],
            [{ type: :radio, width: "full", label: "Open to Product-for-Post Arrangements?" }],
            [{ type: :textarea, width: "full", label: "Why are you a great fit for this brand?" }],
            [{ type: :textarea, width: "full", label: "Previous brand collaborations or notable campaigns" }],
            [{ type: :file, width: "full", label: "Media Kit / Rate Card" }],
            [{ type: :checkbox, width: "full", label: "I confirm all statistics provided are accurate" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "tel" => "half",
              "number" => "half",
              "select" => "half",
              "radio" => "full",
              "checkbox" => "full",
              "textarea" => "full",
              "file" => "full",
              "url" => "half",
            },
            sections: [
              { label: "Creator Profile", match_types: %w[text email tel url] },
              { label: "Audience & Reach", match_types: %w[number select checkbox radio] },
              { label: "Pitch & Media Kit", match_types: %w[textarea file] }
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
