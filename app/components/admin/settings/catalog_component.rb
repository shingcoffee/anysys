# frozen_string_literal: true

module Admin
  module Settings
    # Direct destinations from the same permission-filtered tree as the sidebar.
    class CatalogComponent < ApplicationComponent
      include Admin::Maintenance::Platform::ModuleSettingsHelper

      Group = Struct.new(:key, :label, :description, :icon, :items, keyword_init: true)

      def initialize(nodes:)
        @nodes = Array(nodes)
      end

      def groups
        @groups ||= build_groups
      end

      def empty?
        groups.empty?
      end

      def icon_well_classes(group)
        module_color_classes(group.key.delete_prefix("settings.section."))
      end

      private

      def build_groups
        groups = []
        current = Group.new(key: "settings.section.ungrouped", items: [])
        groups << current
        @nodes.each do |node|
          next if node.key == "settings.overview"

          if node.section_root && !node.link? && node.children.empty?
            current = Group.new(key: node.key, label: node.label, description: node.description, icon: node.icon, items: [])
            groups << current
          else
            current.items.concat(destinations(node))
          end
        end
        groups.reject { |group| group.items.empty? }
      end

      def destinations(node)
        [*(node.link? ? [node] : []), *node.children.flat_map { |child| destinations(child) }]
      end
    end
  end
end
