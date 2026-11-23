# frozen_string_literal: true

module Websites
  module Admin
    # One collection renderer for initial values and the Stimulus item template.
    class ArrayFieldComponent < ApplicationComponent
      attr_reader :field, :items, :field_id, :site_pages, :design

      def initialize(field:, items:, field_id:, site_pages: [], uploadable: false, workspace: false, design: nil)
        @field, @items, @field_id, @site_pages = field, items, field_id, site_pages
        @uploadable, @workspace, @design = uploadable, workspace, design
      end

      def workspace?
        @workspace
      end

      def title_key
        %w[title name question label].find { |key| field[:item_fields].any? { |item| item[:key] == key } }
      end

      def simple?
        field[:item_fields].map { |item| item[:key] } == %w[label value]
      end

      def item_component(item, index:, template: false)
        ArrayItemComponent.new(
          fields: field[:item_fields], item: item, field_id: "#{field_id}_#{template ? 'new' : index}",
          number: index + 1, title_key: title_key, simple: simple?, expanded: index.zero?,
          first: index.zero?, last: index == items.size - 1,
          min_reached: !template && items.size <= field[:min], max_reached: !template && items.size >= field[:max],
          site_pages: site_pages, uploadable: @uploadable, workspace: workspace?
        )
      end

      def add_label
        key = field[:key]
        return t("website.admin.pages.edit.add_item") unless workspace? && %w[cards cells people].include?(key)

        t("website.admin.pages.form.add_#{key}")
      end
    end
  end
end
