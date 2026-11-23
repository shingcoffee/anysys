# frozen_string_literal: true

module FeatureModules
  # Resolves an exit_target hash into a URL string using a four-step fallback chain:
  #   1. session_exit_target (from Invocation)
  #   2. FeatureModules::CustomerAssignment.configuration["exit_landing_page"]
  #   3. module registration's .default_exit_config
  #   4. the customer home of the invocation's audience (guaranteed)
  #
  # +audience+ is who started the handoff: a member's home is the member
  # area and an anonymous visitor's the site root, never the admin dashboard.
  class ExitResolver
    include Rails.application.routes.url_helpers

    ALLOWED_SCHEMES = %w[http https].freeze

    # Allowlist of named routes that may be used as an exit target.
    ALLOWED_ROUTES = %w[customer_home].freeze

    def self.call(**kwargs) = new(**kwargs).call

    def initialize(customer:, module_key:, session_exit_target:, audience: nil)
      @customer   = customer
      @module_key = module_key
      @session    = session_exit_target
      @audience   = audience.to_s
    end

    def call
      fallback_chain.each do |target|
        next if target.nil?
        resolved = resolve_target(target)
        return resolved if resolved
      end
      customer_home
    end

    private

    def fallback_chain
      [
        normalize(@session),
        normalize(customer_override),
        normalize(module_default),
        { "kind" => "customer_home" }
      ]
    end

    def customer_override
      cfm = FeatureModules::CustomerAssignment.joins(:feature_module)
                                  .where(customer_id: @customer.id, status: :active,
                                         feature_modules: { key: @module_key, handoff_enabled: true })
                                  .first
      return nil unless cfm
      parsed = cfm.configuration.is_a?(String) ? JSON.parse(cfm.configuration) : cfm.configuration
      return nil unless parsed.is_a?(Hash)
      parsed["exit_landing_page"]
    rescue JSON::ParserError, TypeError
      nil
    end

    def module_default
      fm = FeatureModules::Module.find_by(key: @module_key)
      fm&.registration_class&.default_exit_config
    end

    def normalize(hash)
      return nil if hash.nil?
      hash.each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }
    end

    def resolve_target(target)
      case target["kind"].to_s
      when "page"          then resolve_page(target)
      when "flowchart"     then resolve_flowchart(target)
      when "url"           then resolve_url(target)
      when "route"         then resolve_route(target)
      when "record"        then resolve_record(target)
      when "customer_home" then customer_home
      end
    end

    def resolve_page(target)
      page = Page.accessible.find_by(id: target["page_id"])
      return nil unless page

      if page.launched && page.public_uuid.present?
        "/#{@customer.id}/page/#{page.public_uuid}"
      else
        "/#{@customer.id}/admin/maintenance/pages/#{page.id}"
      end
    end

    # Flowchart catch-all execution URLs were removed. A flowchart exit target
    # cannot be resolved to a runnable public URL — return nil so the fallback
    # chain continues (customer override → module default → customer home).
    def resolve_flowchart(_target)
      nil
    end

    def resolve_url(target)
      url = target["url"].to_s
      parsed = URI.parse(url)
      return nil unless ALLOWED_SCHEMES.include?(parsed.scheme)
      url
    rescue URI::InvalidURIError
      nil
    end

    def resolve_route(target)
      customer_home if ALLOWED_ROUTES.include?(target["name"].to_s)
    end

    # The record a payment paid for, on the surface its audience reads
    # records from. An anonymous visitor has none, so the chain continues.
    def resolve_record(target)
      entry = EntityEntry.find_by(id: target["entry_id"], entity_id: target["entity_id"], customer_id: @customer.id)
      return nil unless entry

      case @audience
      when EntityAttributeAudience::MEMBER then member_surface_path(@customer.id, "entity_#{entry.entity_id}", entry.id)
      when EntityAttributeAudience::ADMIN, "" then admin_entity_entry_path(@customer.id, entry.entity_id, entry.id)
      end
    end

    def customer_home
      case @audience
      when EntityAttributeAudience::MEMBER then member_dashboard_path(@customer.id)
      when EntityAttributeAudience::PUBLIC then root_path
      else "/#{@customer.id}/admin/dashboard"
      end
    end
  end
end
