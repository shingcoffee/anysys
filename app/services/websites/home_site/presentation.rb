# frozen_string_literal: true

module Websites
  module HomeSite
    # Read-only dispatch context. Identity survives localization's readonly dup.
    class Presentation
      ROLES = %w[platform pricing about contact].freeze
      COMPONENTS = {
        "hero_centered" => "HeroComponent", "ai_preview" => "DraftComponent",
        "feature_grid" => "IndexComponent", "steps" => "IndexComponent",
        "split_image_text" => "StoryComponent", "rich_text" => "StoryComponent",
        "card_grid" => "PerspectiveComponent", "pricing" => "PlansComponent",
        "faq" => "FaqComponent", "cta_band" => "CtaComponent",
        "proof_strip" => "StatsComponent", "logo_cloud" => "MarqueeComponent",
        "comparison_table" => "ComparisonComponent"
      }.freeze

      def self.for(website:, page:)
        return unless website.is_a?(Website) && page.is_a?(WebsitePage)
        return unless website.customer_id == HomeSite::CUSTOMER_ID && page.customer_id == HomeSite::CUSTOMER_ID

        if website.id || page.id || page.website_id
          return unless website.id && page.website_id == website.id
        else
          return unless page.website.equal?(website)
        end
        role = if page.home?
          :home
        elsif ROLES.include?(page.slug)
          page.slug.to_sym
        end
        new(role: role, website: website) if role
      end

      attr_reader :role

      def initialize(role:, website:)
        @role = role
        @website = website
      end

      def component_class(type)
        name = COMPONENTS[type.to_s]
        HomeSite.const_get(name) if name
      end

      # Only the source assistant role (`home_site_<page>_assistant`) gets the
      # showcase; other feature grids keep their page-role variant.
      def variant_for(type, id: nil)
        case type.to_s
        when "hero_centered"
          return :lead if %i[home platform].include?(role)
          %i[pricing about contact].include?(role) ? role : :editorial
        when "feature_grid"
          return :assistant if id.to_s == "home_site_#{role}_assistant"
          return :principles if role == :about
          role == :pricing ? :foundation : :capabilities
        when "steps" then :process
        when "split_image_text" then :story
        when "rich_text" then role == :contact ? :contact_note : :editorial
        when "cta_band" then role == :contact ? :contact_next_steps : :closing
        when "proof_strip" then :stats
        when "logo_cloud" then :marquee
        when "comparison_table" then :comparison
        end
      end

      def header_class = HomeSite::HeaderComponent
      def footer_class = HomeSite::FooterComponent

      def matches_page?(page)
        self.class.for(website: @website, page: page)&.role == role
      end

      # Preserve saved order; never infer pages from slugs alone or from Current.
      def nav_pages(pages)
        Array(pages).select do |page|
          next false unless page.is_a?(WebsitePage)
          same_site = @website.id ? page.website_id == @website.id : page.website.equal?(@website)
          same_site && page.customer_id == @website.customer_id && page.published? && page.nav_visible?
        end
      end
    end
  end
end
