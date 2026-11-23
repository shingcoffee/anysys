# frozen_string_literal: true

module Admin
  module Modules
    # Modules landing: a sectioned catalog of the customer's enabled
    # feature modules with quick links to their records and actions.
    class HubComponent < ApplicationComponent
      SECTION_ORDER = FeatureModules::NavigationOrder::SECTION_ORDER

      attr_reader :modules

      def initialize(modules:)
        @modules = Array(modules)
      end

      def empty?
        modules.empty?
      end

      # Sections in stable order, skipping empty ones. Modules whose key is not
      # mapped land in :other.
      def sections
        grouped = modules.group_by { |mod| section_key(mod) }
        SECTION_ORDER.filter_map do |key|
          mods = grouped[key]
          next if mods.blank?

          { key: key, title: FeatureModules::NavigationOrder.section_label(key), modules: mods }
        end
      end

      def section_key(mod)
        section = mod.respond_to?(:section) ? mod.section : nil
        SECTION_ORDER.include?(section&.to_sym) ? section.to_sym : :other
      end

    end
  end
end
