# frozen_string_literal: true

module Admin
  module Maintenance
    # Maintenance / Modules: the customer's module catalog grouped by section,
    # with an enablement summary, a client-side search and one card per module.
    class ModuleCatalogComponent < ApplicationComponent
      SEARCH_ID = "maintenance-modules-search"

      attr_reader :customer_id, :modules, :open_links

      # owner_assignments is nil for everyone but the platform owner; when
      # present it carries the enabled assignments behind the limits form.
      def initialize(customer_id:, modules:, enabled_ids:, open_links: {}, owner_assignments: nil)
        @customer_id = customer_id
        @modules = Array(modules)
        @enabled_ids = enabled_ids.to_set
        @open_links = open_links
        @owner_assignments = owner_assignments
      end

      def empty? = modules.empty?

      def enabled?(feature_module) = @enabled_ids.include?(feature_module.id)

      def enabled_count = modules.count { |fm| enabled?(fm) }

      def disabled_count = modules.size - enabled_count

      def required_count = modules.count(&:required?)

      def stats
        [
          { key: :enabled, value: enabled_count, dot: "bg-success" },
          { key: :disabled, value: disabled_count, dot: "bg-border-strong" },
          { key: :required, value: required_count, dot: "bg-warning" }
        ]
      end

      def sections
        FeatureModules::NavigationOrder.by_section(FeatureModules::NavigationOrder.sort(modules), &:key)
      end

      def section_label(section) = FeatureModules::NavigationOrder.section_label(section)

      def section_heading_id(section) = "maintenance-modules-section-#{section}"

      def assignment_for(feature_module)
        @owner_assignments&.dig(feature_module.id) if enabled?(feature_module)
      end
    end
  end
end
